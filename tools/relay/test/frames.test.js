import test from 'node:test';
import assert from 'node:assert/strict';
import { FrameParser, encode, T } from '../src/frames.js';

test('encode layout', () => {
    assert.deepEqual([...encode(T.SESSION, Buffer.from([9, 8]))], [1, 0, 2, 9, 8]);
    assert.deepEqual([...encode(T.PEER_LEFT)], [4, 0, 0]);
});

test('multiple frames in one message', () => {
    const p = new FrameParser();
    const frames = p.push(Buffer.concat([encode(1, 'ab'), encode(3, ''), encode(2, 'xyz')]));
    assert.deepEqual(frames.map((f) => [f.type, f.payload.toString()]), [[1, 'ab'], [3, ''], [2, 'xyz']]);
});

test('frame split across messages, even byte by byte', () => {
    const p = new FrameParser();
    const bytes = Buffer.concat([encode(1, 'hello'), encode(2, 'w')]);
    const out = [];
    for (const b of bytes) out.push(...p.push(Buffer.from([b])));
    assert.deepEqual(out.map((f) => f.payload.toString()), ['hello', 'w']);
});

test('split header and trailing partial frame', () => {
    const p = new FrameParser();
    const whole = encode(1, 'abcd');
    assert.equal(p.push(Buffer.concat([encode(3, 'p'), whole.subarray(0, 2)])).length, 1);
    const rest = p.push(whole.subarray(2));
    assert.equal(rest.length, 1);
    assert.equal(rest[0].payload.toString(), 'abcd');
});

test('oversized payload throws', () => {
    const p = new FrameParser(4096);
    assert.throws(() => p.push(Buffer.from([1, 0x20, 0x00])), RangeError);
});
