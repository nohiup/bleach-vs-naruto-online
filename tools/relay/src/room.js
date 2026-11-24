import { randomBytes } from 'node:crypto';

const NICK_RE = /^[A-Za-z0-9 _-]{1,16}$/;

const HP_VALUES = [0.5, 1, 2, 3, 5];
const TIME_VALUES = [30, 60, 90, -1];

/** Normalizes untrusted room settings; every invalid or missing field falls back to its default. */
export function validateSettings(raw) {
    const s = raw && typeof raw === 'object' ? raw : {};
    const delay = s.inputDelay;
    return {
        hp: HP_VALUES.includes(s.hp) ? s.hp : 1,
        time: TIME_VALUES.includes(s.time) ? s.time : 60,
        inputDelay: Number.isInteger(delay) && delay >= 1 && delay <= 6 ? delay : 3,
    };
}

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
        this.settings = null;
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
    join(nick, password, now, settings) {
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
        if (seat.role === 'host') this.settings = validateSettings(settings);
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

    /** Host-only, WAITING-only settings update. @returns {{ok:true}|{ok:false,code:'NOT_HOST'|'SETTINGS_LOCKED'}} */
    updateSettings(seat, settings) {
        if (!seat || seat.role !== 'host' || !this.seats.includes(seat)) return { ok: false, code: 'NOT_HOST' };
        if (this.state !== 'WAITING') return { ok: false, code: 'SETTINGS_LOCKED' };
        this.settings = validateSettings(settings);
        return { ok: true };
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
        this.settings = null;
        return old;
    }
}
