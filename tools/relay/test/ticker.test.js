import test from 'node:test';
import assert from 'node:assert/strict';
import { Ticker, CMD_START, CMD_STOP } from '../src/ticker.js';

const IV = 1000 / 30;

/** Fake clock + scheduler: advance(ms) fires due timers in order, each at its own due time. */
function harness(opts = {}) {
    let t = 1000;
    let timer = null;
    const sent = [];
    const events = [];
    const parse = (b) => {
        const start = b.readUInt32BE(0);
        const n = b.readUInt8(4);
        const frames = [];
        for (let i = 0; i < n; i++) frames.push([b.readInt16BE(5 + i * 4), b.readInt16BE(7 + i * 4)]);
        return { start, frames };
    };
    const tk = new Ticker({
        now: () => t,
        setTimer: (fn, ms) => (timer = { fn, at: t + ms }),
        clearTimer: () => (timer = null),
        onFrame: (b) => sent.push(parse(b)),
        onEvent: (e, f) => events.push([e, f]),
        ...opts,
    });
    const advance = (ms) => {
        const end = t + ms;
        while (timer && timer.at <= end) {
            const x = timer;
            timer = null;
            t = Math.max(t, x.at);
            x.fn();
        }
        t = end;
    };
    /** Jump the clock, then fire the pending timer once (late timer). */
    const late = (ms) => {
        t += ms;
        const x = timer;
        timer = null;
        x.fn();
    };
    return { tk, sent, events, advance, late, hasTimer: () => timer !== null };
}

const both = (tk, epoch = 1) => {
    tk.ctrl('host', CMD_START, epoch);
    tk.ctrl('client', CMD_START, epoch);
};

test('one seat START produces no frames; both with same epoch start ticking', () => {
    const h = harness();
    h.tk.ctrl('host', CMD_START, 1);
    h.advance(500);
    assert.equal(h.sent.length, 0);
    assert.equal(h.tk.running, false);
    h.tk.ctrl('client', CMD_START, 2);
    h.advance(500);
    assert.equal(h.sent.length, 0);
    h.tk.ctrl('client', CMD_START, 1);
    assert.equal(h.tk.running, true);
    h.advance(IV + 1);
    assert.equal(h.sent.length, 1);
    assert.deepEqual(h.events[0], ['tick_start', { epoch: 1 }]);
});

test('frames are numbered from 1 and map host->p1, client->p2 (latest k wins)', () => {
    const h = harness();
    both(h.tk);
    h.tk.input('host', 5);
    h.tk.input('client', -3);
    h.tk.input('host', 7);
    h.advance(IV + 1);
    assert.deepEqual(h.sent[0], { start: 1, frames: [[7, -3]] });
    h.tk.input('client', 9);
    h.advance(IV);
    assert.deepEqual(h.sent[1], { start: 1, frames: [[7, -3], [7, 9]] });
});

test('start resets stored k to 0', () => {
    const h = harness();
    h.tk.input('host', 5);
    h.tk.input('client', 6);
    both(h.tk);
    h.advance(IV + 1);
    assert.deepEqual(h.sent[0].frames, [[0, 0]]);
});

test('each TICK_FRAME repeats the last 4 frames', () => {
    const h = harness();
    both(h.tk);
    for (let i = 1; i <= 10; i++) {
        h.tk.input('host', i);
        h.advance(IV + 0.5);
    }
    const last = h.sent[h.sent.length - 1];
    assert.equal(h.sent.length, 10);
    assert.equal(last.start, 6);
    assert.deepEqual(last.frames.map((f) => f[0]), [6, 7, 8, 9, 10]);
});

test('late timer emits all due frames at once, chunked to <= 64 per message', () => {
    const h = harness();
    both(h.tk);
    h.tk.input('host', 2);
    h.late(IV * 3 + 1);
    assert.equal(h.sent.length, 1);
    assert.equal(h.sent[0].start, 1);
    assert.equal(h.sent[0].frames.length, 3);
    h.late(IV * 100);
    assert.equal(h.tk.frame, 103);
    const tail = h.sent.slice(1);
    assert.ok(tail.every((m) => m.frames.length <= 64));
    const seen = new Set();
    tail.forEach((m) => m.frames.forEach((_, i) => seen.add(m.start + i)));
    for (let n = 4; n <= 103; n++) assert.ok(seen.has(n), `frame ${n}`);
});

test('schedule is drift-free: 3 seconds yields exactly 90 frames', () => {
    const h = harness();
    both(h.tk);
    h.advance(3000);
    assert.equal(h.tk.frame, 90);
});

test('STOP from either seat stops ticking; restart needs both START of next epoch', () => {
    const h = harness();
    both(h.tk, 1);
    h.advance(IV * 2 + 1);
    h.tk.ctrl('client', CMD_STOP, 0);
    const n = h.sent.length;
    assert.equal(h.tk.running, false);
    assert.equal(h.hasTimer(), false);
    h.advance(1000);
    assert.equal(h.sent.length, n);
    assert.equal(h.events[1][0], 'tick_stop');
    // fast seat re-STARTs before the slow seat's STOP arrives
    h.tk.ctrl('host', CMD_STOP, 0);
    h.tk.ctrl('host', CMD_START, 2);
    h.tk.ctrl('client', CMD_STOP, 0);
    h.tk.ctrl('client', CMD_START, 2);
    assert.equal(h.tk.running, true);
    assert.equal(h.tk.epoch, 2);
    h.advance(IV + 1);
    assert.equal(h.sent[h.sent.length - 1].start, 1);
});

test('START with epoch <= running is ignored; higher epoch from one seat stops ticking', () => {
    const h = harness();
    both(h.tk, 2);
    h.advance(IV + 1);
    h.tk.ctrl('host', CMD_START, 2);
    h.tk.ctrl('client', CMD_START, 1);
    assert.equal(h.tk.running, true);
    assert.equal(h.tk.frame, 1);
    h.tk.ctrl('host', CMD_START, 3);
    assert.equal(h.tk.running, false);
    const n = h.sent.length;
    h.advance(500);
    assert.equal(h.sent.length, n);
    h.tk.ctrl('client', CMD_START, 3);
    assert.equal(h.tk.running, true);
    assert.equal(h.tk.epoch, 3);
    assert.equal(h.tk.frame, 0);
});

test('reset (peer leave / room reset / shutdown) stops ticking and clears pending STARTs', () => {
    const h = harness();
    both(h.tk);
    h.advance(IV + 1);
    h.tk.reset('room_reset');
    assert.equal(h.tk.running, false);
    assert.equal(h.hasTimer(), false);
    h.tk.ctrl('client', CMD_START, 1);
    assert.equal(h.tk.running, false);
});

test('input while not ticking only stores k; unknown roles ignored', () => {
    const h = harness();
    h.tk.input('host', 4);
    h.tk.input('nobody', 4);
    h.tk.ctrl('nobody', CMD_START, 1);
    assert.equal(h.tk.k.host, 4);
    assert.equal(h.sent.length, 0);
});

const lastN = (h) => {
    const m = h.sent[h.sent.length - 1];
    return m ? m.start + m.frames.length - 1 : 0;
};

test('backpressure: frames stop at minLast + maxLead', () => {
    const h = harness({ maxLead: 5 });
    both(h.tk);
    h.tk.input('host', 0, 3);
    h.tk.input('client', 0, 2);
    h.advance(2000);
    assert.equal(lastN(h), 7);
    assert.equal(h.tk.frame, 7);
});

test('backpressure: resumes at 30 Hz after lastFrame advances, no burst', () => {
    const h = harness({ maxLead: 5 });
    both(h.tk);
    h.advance(2000);
    assert.equal(lastN(h), 5);
    const count = h.sent.length;
    h.tk.input('host', 0, 1000);
    h.tk.input('client', 0, 1000);
    h.advance(IV * 0.9);
    assert.ok(h.sent.length - count <= 1, 'no burst on release');
    h.advance(IV * 9.1);
    const n = lastN(h) - 5;
    assert.ok(n >= 9 && n <= 10, `30 Hz after release, got ${n}`);
    assert.equal(h.sent.length - count, n);
});

test('backpressure: one slow seat holds both', () => {
    const h = harness({ maxLead: 4 });
    both(h.tk);
    h.tk.input('host', 0, 1000);
    h.tk.input('client', 0, 1);
    h.advance(2000);
    assert.equal(lastN(h), 5);
    h.tk.input('client', 0, 3);
    h.advance(IV * 10);
    assert.equal(lastN(h), 7);
});

test('backpressure: lastFrame resets on new epoch', () => {
    const h = harness({ maxLead: 5 });
    both(h.tk, 1);
    h.tk.input('host', 0, 50);
    h.tk.input('client', 0, 50);
    h.advance(1000);
    assert.ok(lastN(h) > 20);
    both(h.tk, 2);
    h.sent.length = 0;
    h.advance(2000);
    assert.equal(lastN(h), 5);
});

test('backpressure: late timer catch-up is bounded by maxLead', () => {
    const h = harness({ maxLead: 5 });
    both(h.tk);
    h.tk.input('host', 0, 100);
    h.tk.input('client', 0, 100);
    h.late(10 * IV + 1);
    assert.equal(lastN(h), 10);
    h.tk.input('host', 0, 0);
    h.tk.input('client', 0, 0);
    h.late(20 * IV);
    assert.equal(lastN(h), 10);
    h.tk.input('host', 0, 10);
    h.tk.input('client', 0, 10);
    h.late(20 * IV);
    assert.equal(lastN(h), 15);
});

test('backpressure: tick_hold logged at most once per second', () => {
    const h = harness({ maxLead: 3 });
    both(h.tk);
    h.advance(2500);
    const holds = h.events.filter(([e]) => e === 'tick_hold');
    assert.ok(holds.length >= 2 && holds.length <= 3);
    assert.equal(holds[0][1].frame, 3);
});
