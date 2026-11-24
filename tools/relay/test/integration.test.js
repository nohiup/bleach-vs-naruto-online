import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import WebSocket from 'ws';
import { createRelay } from '../src/server.js';
import { encode, FrameParser, T } from '../src/frames.js';

console.log = () => {};

const DEF = { hp: 1, time: 60, inputDelay: 3 };

/** Wraps a ws with a message queue so tests can await the next matching message. */
function client(url, opts) {
    const ws = new WebSocket(url, opts);
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
    const opened = new Promise((r, j) => {
        ws.on('open', r);
        ws.on('unexpected-response', (_q, res) => j(new Error(String(res.statusCode))));
    });
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

async function start(env) {
    const relay = createRelay({ tokenTtlMs: 15000, idleTimeoutMs: 10000, ...env });
    const port = await relay.listen(0);
    return { relay, base: `ws://127.0.0.1:${port}`, port };
}

test('health and 404', async () => {
    const { relay, port } = await start();
    const get = (path) => new Promise((r) => http.get({ port, path }, (res) => {
        let body = '';
        res.on('data', (d) => (body += d));
        res.on('end', () => r([res.statusCode, body]));
    }));
    assert.deepEqual(await get('/health'), [200, 'ok']);
    assert.equal((await get('/nope'))[0], 404);
    await relay.close();
});

test('full flow: lobby join, HELLO, PEER_READY, forward, disconnect resets', async () => {
    const { relay, base } = await start();
    const l1 = client(`${base}/lobby`);
    const l2 = client(`${base}/lobby`);
    await Promise.all([l1.opened, l2.opened]);
    assert.deepEqual(await l1.next(), { t: 'status', state: 'EMPTY', players: [], settings: null });
    await l2.next();
    l1.ws.send(JSON.stringify({ t: 'join', nick: 'Ichigo' }));
    const j1 = await l1.next();
    assert.equal(j1.t, 'joined');
    assert.equal(j1.role, 'host');
    assert.deepEqual(await l1.next(), { t: 'status', state: 'WAITING', players: ['Ichigo'], settings: DEF });
    assert.deepEqual(await l2.next(), { t: 'status', state: 'WAITING', players: ['Ichigo'], settings: DEF });
    l2.ws.send(JSON.stringify({ t: 'join', nick: 'Naruto' }));
    const j2 = await l2.next();
    assert.equal(j2.role, 'client');
    assert.equal((await l2.next()).state, 'PLAYING');
    await l1.next();

    const g1 = client(`${base}/game`);
    const g2 = client(`${base}/game`);
    await Promise.all([g1.opened, g2.opened]);
    g1.ws.send(encode(T.HELLO, j1.token));
    const ok1 = await g1.next();
    assert.equal(ok1.type, T.HELLO);
    assert.equal(ok1.payload.toString(), 'host');
    g1.ws.send(encode(T.SESSION, 'early'));
    g1.ws.send(encode(T.PING, 'p1'));
    assert.equal((await g1.next()).payload.toString(), 'p1');
    g2.ws.send(encode(T.HELLO, j2.token));
    assert.equal((await g2.next()).payload.toString(), 'client');
    assert.equal((await g1.next()).type, T.PEER_READY);
    assert.equal((await g2.next()).type, T.PEER_READY);

    // the 'early' SESSION was dropped; forwarded frames arrive in order, split + merged
    const f = encode(T.SESSION, 'hi');
    g1.ws.send(f.subarray(0, 2));
    g1.ws.send(Buffer.concat([f.subarray(2), encode(T.INPUT, 'in')]));
    const a = await g2.next();
    const b = await g2.next();
    assert.deepEqual([a.type, a.payload.toString(), b.type, b.payload.toString()], [T.SESSION, 'hi', T.INPUT, 'in']);

    g1.ws.close();
    const left = await g2.next();
    assert.equal(left.type, T.PEER_LEFT);
    await g2.closed;
    assert.deepEqual(await l2.next(), { t: 'reset', reason: 'PEER_LEFT' });
    assert.deepEqual(await l2.next(), { t: 'status', state: 'EMPTY', players: [], settings: null });
    assert.equal(relay.room.state, 'EMPTY');
    assert.deepEqual(await l1.next(), { t: 'status', state: 'EMPTY', players: [], settings: null });
    [l1, l2].forEach((c) => c.ws.close());
    await relay.close();
});

test('bad HELLO token closes game socket', async () => {
    const { relay, base } = await start();
    const g = client(`${base}/game`);
    await g.opened;
    g.ws.send(encode(T.HELLO, 'deadbeef'));
    assert.equal(await g.closed, 1008);
    await relay.close();
});

test('ROOM_FULL and ALREADY_JOINED over lobby', async () => {
    const { relay, base } = await start();
    const cs = [client(`${base}/lobby`), client(`${base}/lobby`), client(`${base}/lobby`)];
    await Promise.all(cs.map((c) => c.opened));
    cs[0].ws.send(JSON.stringify({ t: 'join', nick: 'a' }));
    cs[0].ws.send(JSON.stringify({ t: 'join', nick: 'a' }));
    cs[1].ws.send(JSON.stringify({ t: 'join', nick: 'b' }));
    cs[2].ws.send(JSON.stringify({ t: 'join', nick: 'c' }));
    let m;
    do m = await cs[2].next(); while (m.t !== 'error');
    assert.equal(m.code, 'ROOM_FULL');
    do m = await cs[0].next(); while (m.t !== 'error');
    assert.equal(m.code, 'ALREADY_JOINED');
    cs.forEach((c) => c.ws.close());
    await relay.close();
});

test('unclaimed token expires and resets room', async () => {
    const { relay, base } = await start({ tokenTtlMs: 100 });
    const l = client(`${base}/lobby`);
    await l.opened;
    l.ws.send(JSON.stringify({ t: 'join', nick: 'a' }));
    let m;
    do m = await l.next(); while (m.t !== 'reset');
    assert.equal(m.reason, 'TIMEOUT');
    assert.equal(relay.room.state, 'EMPTY');
    l.ws.close();
    await relay.close();
});

test('origin check', async () => {
    const { relay, base } = await start({ allowedOrigins: ['https://good.example'] });
    await assert.rejects(client(`${base}/lobby`, { origin: 'https://evil.example' }).opened, /403/);
    const ok = client(`${base}/lobby`, { origin: 'https://good.example' });
    await ok.opened;
    ok.ws.close();
    await relay.close();
});

const send = (c, o) => c.ws.send(JSON.stringify(o));

test('settings: host join with settings, update while WAITING, NOT_HOST, LOCKED, reset clears', async () => {
    const { relay, base } = await start();
    const l1 = client(`${base}/lobby`);
    const l2 = client(`${base}/lobby`);
    const l3 = client(`${base}/lobby`);
    await Promise.all([l1.opened, l2.opened, l3.opened]);
    for (const l of [l1, l2, l3]) assert.equal((await l.next()).settings, null);
    const S = { hp: 2, time: 90, inputDelay: 5 };
    send(l1, { t: 'join', nick: 'Host', settings: S });
    const j1 = await l1.next();
    assert.deepEqual(j1.settings, S);
    assert.deepEqual((await l1.next()).settings, S);
    await l2.next();
    await l3.next();
    // unseated socket
    send(l3, { t: 'settings', settings: DEF });
    assert.deepEqual(await l3.next(), { t: 'error', code: 'NOT_HOST' });
    // host update (invalid fields fall back to defaults)
    send(l1, { t: 'settings', settings: { hp: 3, time: 7, inputDelay: 9 } });
    const upd = { hp: 3, time: 60, inputDelay: 3 };
    assert.deepEqual((await l1.next()).settings, upd);
    assert.deepEqual((await l3.next()).settings, upd);
    await l2.next();
    // client join ignores its settings and receives room settings
    send(l2, { t: 'join', nick: 'Guest', settings: { hp: 5, time: 30, inputDelay: 1 } });
    assert.deepEqual((await l2.next()).settings, upd);
    assert.deepEqual((await l2.next()).settings, upd);
    await l1.next();
    // client cannot change
    send(l2, { t: 'settings', settings: DEF });
    assert.deepEqual(await l2.next(), { t: 'error', code: 'NOT_HOST' });
    // host locked while PLAYING
    send(l1, { t: 'settings', settings: DEF });
    assert.deepEqual(await l1.next(), { t: 'error', code: 'SETTINGS_LOCKED' });
    assert.equal(relay.room.settings.hp, 3);
    // reset clears
    send(l1, { t: 'leave' });
    assert.equal((await l3.next()).state, 'PLAYING');
    const st = await l3.next();
    assert.deepEqual([st.state, st.settings], ['EMPTY', null]);
    assert.equal(relay.room.settings, null);
    await relay.close();
});

test('settings: join without or with invalid settings uses defaults', async () => {
    for (const settings of [undefined, 'x', { hp: 4, time: 45, inputDelay: 0 }, { hp: '2', inputDelay: 2.5 }]) {
        const { relay, base } = await start();
        const l = client(`${base}/lobby`);
        await l.opened;
        await l.next();
        send(l, { t: 'join', nick: 'H', settings });
        assert.deepEqual((await l.next()).settings, DEF);
        await relay.close();
    }
});
