export const CMD_START = 1;
export const CMD_STOP = 2;
export const TICK_HZ = 30;
export const REDUNDANCY = 4;
export const MAX_FRAMES_PER_MSG = 64;

const INTERVAL_MS = 1000 / TICK_HZ;
const EPS = 1e-6;

/** Builds a TICK_FRAME payload: `[u32 startFrame][u8 count]` + count x `[i16 p1K][i16 p2K]`. */
export function encodeTickFrame(startFrame, pairs) {
    const out = Buffer.allocUnsafe(5 + pairs.length * 4);
    out.writeUInt32BE(startFrame, 0);
    out.writeUInt8(pairs.length, 4);
    pairs.forEach(([p1, p2], i) => {
        out.writeInt16BE(p1, 5 + i * 4);
        out.writeInt16BE(p2, 7 + i * 4);
    });
    return out;
}

/**
 * Pure per-room tick state machine (relay-paced fight frames). No I/O.
 * Roles are 'host' (p1) and 'client' (p2). The clock and scheduler are injected:
 *   now()               monotonic milliseconds (float)
 *   setTimer(fn, ms)    returns a handle; clearTimer(handle) cancels it
 *   onFrame(payload)    called with each TICK_FRAME payload to send to both seats
 *   onEvent(name, data) optional logging hook ('tick_start' | 'tick_stop')
 */
export class Ticker {
    constructor({ now, setTimer, clearTimer, onFrame, onEvent = () => {} }) {
        this.now = now;
        this.setTimer = setTimer;
        this.clearTimer = clearTimer;
        this.onFrame = onFrame;
        this.onEvent = onEvent;
        this.running = false;
        this.epoch = 0;
        this.frame = 0;
        this.k = { host: 0, client: 0 };
        this.history = [];
        this.pending = { host: 0, client: 0 };
        this.timer = null;
        this.t0 = 0;
    }

    /** TICK_CTRL from a seat. */
    ctrl(role, cmd, epoch) {
        if (role !== 'host' && role !== 'client') return;
        if (cmd === CMD_STOP) {
            this.pending[role] = 0;
            if (this.running) this.stop('stop', role);
            return;
        }
        if (cmd !== CMD_START) return;
        if (this.running) {
            if (epoch <= this.epoch) return;
            this.stop('higher_epoch', role);
        }
        this.pending[role] = epoch;
        const peer = role === 'host' ? 'client' : 'host';
        if (this.pending[peer] === epoch) this.start(epoch);
    }

    /** TICK_INPUT from a seat: stores the latest k (also while not ticking). */
    input(role, k) {
        if (role === 'host' || role === 'client') this.k[role] = k;
    }

    start(epoch) {
        this.pending.host = this.pending.client = 0;
        this.running = true;
        this.epoch = epoch;
        this.frame = 0;
        this.history = [];
        this.k.host = this.k.client = 0;
        this.t0 = this.now();
        this.onEvent('tick_start', { epoch });
        this.schedule();
    }

    /** Stops ticking (no-op when idle). `reason` is only used for logging. */
    stop(reason = 'stop', by = null) {
        if (this.timer !== null) this.clearTimer(this.timer);
        this.timer = null;
        if (!this.running) return;
        this.running = false;
        this.onEvent('tick_stop', { epoch: this.epoch, frame: this.frame, reason, by });
    }

    /** Full reset (room reset / peer leave / shutdown): stops and forgets pending STARTs. */
    reset(reason = 'reset') {
        this.stop(reason);
        this.pending.host = this.pending.client = 0;
        this.k.host = this.k.client = 0;
    }

    schedule() {
        const at = this.t0 + (this.frame + 1) * INTERVAL_MS;
        const delay = Math.max(0, Math.ceil(at - this.now()));
        this.timer = this.setTimer(() => this.fire(), delay);
    }

    fire() {
        this.timer = null;
        if (!this.running) return;
        const due = Math.floor((this.now() - this.t0) / INTERVAL_MS + EPS);
        const first = this.frame + 1;
        while (this.frame < due) {
            this.history.push([this.k.host, this.k.client]);
            this.frame++;
        }
        if (this.frame >= first) this.emit(first, this.frame);
        if (this.history.length > 64) this.history.splice(0, this.history.length - 64);
        this.schedule();
    }

    /** Sends frames `first..last`, each message prefixed with up to REDUNDANCY older frames. */
    emit(first, last) {
        const base = this.frame - this.history.length + 1;
        for (let from = first; from <= last; ) {
            const to = Math.min(last, from + MAX_FRAMES_PER_MSG - REDUNDANCY - 1);
            const start = Math.max(1, from - REDUNDANCY, base);
            this.onFrame(encodeTickFrame(start, this.history.slice(start - base, to - base + 1)));
            from = to + 1;
        }
    }
}
