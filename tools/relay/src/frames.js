export const T = { HELLO: 0, SESSION: 1, INPUT: 2, PING: 3, PEER_LEFT: 4, PEER_READY: 5 };
export const MAX_PAYLOAD = 4096;
const HEADER = 3;

export function encode(type, payload = Buffer.alloc(0)) {
    const body = typeof payload === 'string' ? Buffer.from(payload, 'utf8') : Buffer.from(payload);
    if (body.length > 0xffff) throw new RangeError('payload too large');
    const out = Buffer.allocUnsafe(HEADER + body.length);
    out.writeUInt8(type, 0);
    out.writeUInt16BE(body.length, 1);
    body.copy(out, HEADER);
    return out;
}

/** Incremental parser for the `[u8 type][u16 BE len][payload]` byte stream. */
export class FrameParser {
    constructor(maxPayload = MAX_PAYLOAD) {
        this.maxPayload = maxPayload;
        this.buf = Buffer.alloc(0);
    }

    /** Feeds bytes; returns complete frames. Throws RangeError when a frame exceeds maxPayload. */
    push(chunk) {
        this.buf = this.buf.length ? Buffer.concat([this.buf, chunk]) : Buffer.from(chunk);
        const frames = [];
        let off = 0;
        while (this.buf.length - off >= HEADER) {
            const len = this.buf.readUInt16BE(off + 1);
            if (len > this.maxPayload) throw new RangeError('frame payload too large');
            if (this.buf.length - off < HEADER + len) break;
            frames.push({ type: this.buf[off], payload: this.buf.subarray(off + HEADER, off + HEADER + len) });
            off += HEADER + len;
        }
        this.buf = this.buf.subarray(off);
        return frames;
    }
}
