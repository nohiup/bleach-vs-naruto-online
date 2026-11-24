import test from 'node:test';
import assert from 'node:assert/strict';
import { Room } from '../src/room.js';

const mk = (opts) => new Room({ tokenTtlMs: 15000, idleTimeoutMs: 10000, ...opts });

test('join order host/client then ROOM_FULL', () => {
    const r = mk();
    assert.equal(r.state, 'EMPTY');
    const a = r.join('Ichigo', '', 0);
    assert.equal(a.seat.role, 'host');
    assert.equal(r.state, 'WAITING');
    const b = r.join('Naruto', '', 0);
    assert.equal(b.seat.role, 'client');
    assert.equal(r.state, 'PLAYING');
    assert.deepEqual(r.join('Third', '', 0), { ok: false, code: 'ROOM_FULL' });
    assert.deepEqual(r.players, ['Ichigo', 'Naruto']);
    assert.match(a.seat.token, /^[0-9a-f]{32}$/);
});

test('nick validation', () => {
    const r = mk();
    for (const bad of ['', 'a'.repeat(17), 'bad!', 'é', null, undefined]) {
        assert.equal(r.join(bad, '', 0).code, 'BAD_NICK');
    }
    assert.ok(r.join('ok_Nick-1 x', '', 0).ok);
});

test('room password', () => {
    const r = mk({ password: 'pw' });
    assert.equal(r.join('a', 'nope', 0).code, 'BAD_PASSWORD');
    assert.ok(r.join('a', 'pw', 0).ok);
});

test('token expiry frees via findTimedOut and claim fails', () => {
    const r = mk();
    const { seat } = r.join('a', '', 0);
    assert.equal(r.findTimedOut(15000), null);
    assert.equal(r.findTimedOut(15001), seat);
    assert.equal(r.claim(seat.token, 15001), null);
    assert.ok(r.claim(seat.token, 14000));
});

test('claim: unknown token and double claim rejected; ready when both claimed', () => {
    const r = mk();
    const a = r.join('a', '', 0).seat;
    const b = r.join('b', '', 0).seat;
    assert.equal(r.claim('nope', 1), null);
    assert.equal(r.claim(a.token, 1).ready, false);
    assert.equal(r.claim(a.token, 1), null);
    assert.equal(r.claim(b.token, 2).ready, true);
});

test('forwarding blocked before ready', () => {
    const r = mk();
    const a = r.join('a', '', 0).seat;
    const b = r.join('b', '', 0).seat;
    r.claim(a.token, 1);
    assert.equal(r.canForward(), false);
    r.claim(b.token, 1);
    assert.equal(r.canForward(), true);
    assert.equal(r.peerOf(a), b);
});

test('idle timeout after claim', () => {
    const r = mk();
    const a = r.join('a', '', 0).seat;
    r.claim(a.token, 0);
    r.touch(a, 5000);
    assert.equal(r.findTimedOut(15000), null);
    assert.equal(r.findTimedOut(15001), a);
});

test('any seat leaving resets room to EMPTY', () => {
    const r = mk();
    const a = r.join('a', '', 0).seat;
    r.join('b', '', 0);
    assert.equal(r.leave(a).length, 2);
    assert.equal(r.state, 'EMPTY');
    assert.equal(r.leave(a).length, 0);
    assert.equal(r.join('c', '', 0).seat.role, 'host');
});
