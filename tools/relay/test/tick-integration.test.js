import test from 'node:test';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import { createRelay } from '../src/server.js';
import { encode, FrameParser, T } from '../src/frames.js';

console.log = () => {};

function client(url) {
    const ws = new WebSocket(url);
    const queue = [];
    const waiters = [];
    const parser = new FrameParser();
    const push = (m) => {
        const w = waiters.shift();
        if (w) w(m);
        else queue.push(m);
    };
    ws.on('message', (data, isBinary) => {
        if (!isBinary) return push(JSON.parse(data.toString()));
        parser.push(data).forEach(push);
    });
    const closed = new Promise((r) => ws.on('close', (code) => r(code)));
    ws.on('error', () => {});
    const opened = new Promise((r) => ws.on('open', r));
    const next = (ms = 2000) =>
        queue.length
            ? Promise.resolve(queue.shift())
            : new Promise((res, rej) => {
                  const t = setTimeout(() => rej(new Error('timeout waiting for message')), ms);
                  waiters.push((m) => {
                      clearTimeout(t);
                      res(m);
                  });
              });
    return { ws, opened, closed, next, queue };
}

const ctrl = (cmd, epoch) => {
    const b = Buffer.alloc(5);
    b.writeUInt8(cmd, 0);
    b.writeUInt32BE(epoch, 1);
    return encode(T.TICK_CTRL, b);
};
const tickIn = (last, k) => {
    const b = Buffer.alloc(6);
    b.writeUInt32BE(last, 0);
    b.writeInt16BE(k, 4);
    return encode(T.TICK_INPUT, b);
};
const until = async (c, pred, n = 200) => {
    for (let i = 0; i < n; i++) {
        const m = await c.next();
        if (pred(m)) return m;
    }
    throw new Error('not found');
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
/** Last (newest) frame pair of a TICK_FRAME payload. */
const newest = (p) => {
    const n = p[4];
    return { frame: p.readUInt32BE(0) + n - 1, n, p1: p.readInt16BE(5 + (n - 1) * 4), p2: p.readInt16BE(7 + (n - 1) * 4) };
};

async function seated(env) {
    const relay = createRelay({ tokenTtlMs: 15000, idleTimeoutMs: 10000, ...env });
    const port = await relay.listen(0);
    const base = `ws://127.0.0.1:${port}`;
    const l1 = client(`${base}/lobby`);
    const l2 = client(`${base}/lobby`);
    await Promise.all([l1.opened, l2.opened]);
    l1.ws.send(JSON.stringify({ t: 'join', nick: 'A' }));
    const j1 = await until(l1, (m) => m.t === 'joined');
    l2.ws.send(JSON.stringify({ t: 'join', nick: 'B' }));
    const j2 = await until(l2, (m) => m.t === 'joined');
    const g1 = client(`${base}/game`);
    const g2 = client(`${base}/game`);
    await Promise.all([g1.opened, g2.opened]);
    g1.ws.send(encode(T.HELLO, j1.token));
    g2.ws.send(encode(T.HELLO, j2.token));
    await until(g1, (m) => m.type === T.PEER_READY);
    await until(g2, (m) => m.type === T.PEER_READY);
    const done = async () => {
        [g1, g2, l1, l2].forEach((c) => c.ws.close());
        await relay.close();
    };
    return { relay, g1, g2, done };
}

test('relay-paced: no frames until both START; inputs mapped; 6/7 not forwarded; STOP halts', async () => {
    const { g1, g2, done } = await seated();
    g1.ws.send(ctrl(1, 1));
    g1.ws.send(tickIn(0, 3));
    await sleep(150);
    assert.equal(g1.queue.length, 0);
    assert.equal(g2.queue.length, 0);
    g2.ws.send(ctrl(1, 1));
    g2.ws.send(tickIn(0, -2));
    g1.ws.send(tickIn(0, 3));
    const f1 = await until(g1, (m) => m.type === T.TICK_FRAME);
    const f2 = await until(g2, (m) => m.type === T.TICK_FRAME);
    assert.equal(f1.payload.readUInt32BE(0), 1);
    assert.equal(f2.payload.readUInt32BE(0), 1);
    const m = await until(g1, (x) => x.type === T.TICK_FRAME && newest(x.payload).frame >= 8);
    assert.deepEqual([newest(m.payload).p1, newest(m.payload).p2], [3, -2]);
    assert.ok(m.payload[4] <= 8);
    g1.ws.send(ctrl(2, 1));
    await sleep(120);
    g1.queue.length = 0;
    g2.queue.length = 0;
    await sleep(200);
    assert.equal(g1.queue.length, 0);
    assert.equal(g2.queue.length, 0);
    await done();
});

test('relay-paced: peer leave stops ticking', async () => {
    const { relay, g1, g2, done } = await seated();
    g1.ws.send(ctrl(1, 1));
    g2.ws.send(ctrl(1, 1));
    await until(g2, (m) => m.type === T.TICK_FRAME);
    assert.equal(relay.ticker.running, true);
    g1.ws.close();
    await g2.closed;
    assert.equal(relay.ticker.running, false);
    await done();
});

test('relay-paced: SIM_DELAY_MS delays both uplink and downlink', async () => {
    const { g1, g2, done } = await seated({ simDelayMs: 80 });
    const t0 = Date.now();
    g1.ws.send(ctrl(1, 1));
    g2.ws.send(ctrl(1, 1));
    await until(g1, (m) => m.type === T.TICK_FRAME);
    assert.ok(Date.now() - t0 >= 150, `elapsed ${Date.now() - t0}`);
    await done();
});

test('backpressure: a client that stops sending TICK_INPUT stalls frames after maxLead', async () => {
    const { g1, g2, done } = await seated({ tickMaxLead: 6 });
    g1.ws.send(ctrl(1, 1));
    g2.ws.send(ctrl(1, 1));
    const pump = setInterval(() => g1.ws.send(tickIn(newestSeen(g1), 1)), 20);
    let seen = 0;
    const newestSeen = () => seen;
    const track = setInterval(() => {
        for (const m of g1.queue) if (m.type === T.TICK_FRAME) seen = Math.max(seen, newest(m.payload).frame);
    }, 5);
    await sleep(700);
    clearInterval(pump);
    clearInterval(track);
    for (const m of g1.queue) if (m.type === T.TICK_FRAME) seen = Math.max(seen, newest(m.payload).frame);
    assert.equal(seen, 6);
    await done();
});
