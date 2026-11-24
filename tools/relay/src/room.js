import { randomBytes } from 'node:crypto';

const NICK_RE = /^[A-Za-z0-9 _-]{1,16}$/;

/**
 * Pure single-room state machine (2 seats). No I/O, time is passed in.
 * Seat objects are plain; callers may attach their own fields (sockets) to them.
 */
export class Room {
    constructor({ password = '', tokenTtlMs = 15000, idleTimeoutMs = 10000 } = {}) {
        this.password = password;
        this.tokenTtlMs = tokenTtlMs;
        this.idleTimeoutMs = idleTimeoutMs;
        this.seats = [];
    }

    get state() {
        return ['EMPTY', 'WAITING', 'PLAYING'][this.seats.length];
    }

    get players() {
        return this.seats.map((s) => s.nick);
    }

    get ready() {
        return this.seats.length === 2 && this.seats.every((s) => s.claimed);
    }

    /** @returns {{ok:true,seat:object}|{ok:false,code:string}} */
    join(nick, password, now) {
        if (typeof nick !== 'string' || !NICK_RE.test(nick)) return { ok: false, code: 'BAD_NICK' };
        if (this.password && password !== this.password) return { ok: false, code: 'BAD_PASSWORD' };
        if (this.seats.length >= 2) return { ok: false, code: 'ROOM_FULL' };
        const seat = {
            role: this.seats.length === 0 ? 'host' : 'client',
            nick,
            token: randomBytes(16).toString('hex'),
            claimed: false,
            expiresAt: now + this.tokenTtlMs,
            lastSeen: now,
        };
        this.seats.push(seat);
        return { ok: true, seat };
    }

    /** Claims a seat with its token. @returns {{seat:object,ready:boolean}|null} */
    claim(token, now) {
        const seat = this.seats.find((s) => s.token === token);
        if (!seat || seat.claimed || now > seat.expiresAt) return null;
        seat.claimed = true;
        seat.lastSeen = now;
        return { seat, ready: this.ready };
    }

    touch(seat, now) {
        seat.lastSeen = now;
    }

    peerOf(seat) {
        return this.seats.find((s) => s !== seat) || null;
    }

    canForward() {
        return this.ready;
    }

    /** First seat whose token expired unclaimed or that has been idle too long. */
    findTimedOut(now) {
        return this.seats.find((s) => (s.claimed ? now - s.lastSeen > this.idleTimeoutMs : now > s.expiresAt)) || null;
    }

    /** Removes a seat; the whole room resets. @returns the seats that were seated, or [] if seat was stale. */
    leave(seat) {
        if (!this.seats.includes(seat)) return [];
        return this.reset();
    }

    reset() {
        const old = this.seats;
        this.seats = [];
        return old;
    }
}
