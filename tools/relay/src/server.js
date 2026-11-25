import http from 'node:http';
import { pathToFileURL } from 'node:url';
import { WebSocketServer } from 'ws';
import { Room } from './room.js';
import { performance } from 'node:perf_hooks';
import { Ticker } from './ticker.js';
import { FrameParser, encode, T, MAX_PAYLOAD } from './frames.js';

const OPEN = 1;
const MAX_FRAMES_PER_SEC = 120;
const MAX_CONN_PER_IP = 5;
const MAX_JOINS_PER_10S = 5;

export function configFromEnv(env = process.env) {
    return {
        port: Number(env.PORT) || 8080,
        allowedOrigins: (env.ALLOWED_ORIGIN || '').split(',').map((s) => s.trim()).filter(Boolean),
        password: env.ROOM_PASSWORD || '',
        tokenTtlMs: Number(env.TOKEN_TTL_MS) || 15000,
        idleTimeoutMs: Number(env.IDLE_TIMEOUT_MS) || 10000,
        trustProxy: env.TRUST_PROXY === '1',
        // test only: delay every forwarded SESSION/INPUT frame by this many ms to simulate WAN latency
        simDelayMs: Math.max(0, Number(env.SIM_DELAY_MS) || 0),
        // relay-paced ticks: max frames the relay may run ahead of the slowest client's lastFrame
        tickMaxLead: Math.max(1, Math.floor(Number(env.TICK_MAX_LEAD)) || 12),
    };
}

function log(event, fields = {}) {
    console.log(JSON.stringify({ ts: new Date().toISOString(), event, ...fields }));
}

function send(ws, data) {
    if (ws && ws.readyState === OPEN) ws.send(data);
}

/** Fixed one-second window counter; hit() returns false once the limit is exceeded. */
function rateLimiter(limit, windowMs) {
    let start = 0;
    let count = 0;
    return (now) => {
        if (now - start >= windowMs) {
            start = now;
            count = 0;
        }
        return ++count <= limit;
    };
}

export function createRelay(overrides = {}) {
    const cfg = { ...configFromEnv({}), ...overrides };
    const room = new Room({ password: cfg.password, tokenTtlMs: cfg.tokenTtlMs, idleTimeoutMs: cfg.idleTimeoutMs });
    const delayed = new Set();
    const later = (fn) => {
        if (cfg.simDelayMs <= 0) return fn();
        const t = setTimeout(() => {
            delayed.delete(t);
            fn();
        }, cfg.simDelayMs);
        delayed.add(t);
    };
    const ticker = new Ticker({
        now: () => performance.now(),
        setTimer: (fn, ms) => setTimeout(fn, ms),
        clearTimer: (h) => clearTimeout(h),
        onFrame: (payload) => {
            const out = encode(T.TICK_FRAME, payload);
            later(() => room.seats.forEach((s) => send(s.game, out)));
        },
        onEvent: (event, fields) => log(event, fields),
        maxLead: cfg.tickMaxLead,
    });
    const lobbies = new Set();
    const ipCounts = new Map();
    if (!cfg.allowedOrigins.length) log('warn', { msg: 'ALLOWED_ORIGIN unset, allowing all origins' });

    const server = http.createServer((req, res) => {
        const ok = req.method === 'GET' && new URL(req.url, 'http://x').pathname === '/health';
        res.writeHead(ok ? 200 : 404, { 'Content-Type': 'text/plain' });
        res.end(ok ? 'ok' : 'not found');
    });
    const lobbyWss = new WebSocketServer({ noServer: true, maxPayload: 2048 });
    const gameWss = new WebSocketServer({ noServer: true, maxPayload: 65536 });

    const statusMsg = () => JSON.stringify({ t: 'status', state: room.state, players: room.players, settings: room.settings });

    function broadcastStatus() {
        const msg = statusMsg();
        lobbies.forEach((ws) => send(ws, msg));
    }

    /** Resets the room because `initiator` left or timed out; notifies and closes the other side. */
    function resetRoom(reason, initiator) {
        if (!room.seats.includes(initiator)) return;
        ticker.reset('room_reset');
        const seats = room.reset();
        log('reset', { reason, by: initiator.role, nick: initiator.nick });
        for (const seat of seats) {
            const other = seat !== initiator;
            const { lobby, game } = seat;
            seat.lobby = seat.game = null;
            if (lobby) {
                lobby.seat = null;
                if (other || reason === 'TIMEOUT') send(lobby, JSON.stringify({ t: 'reset', reason }));
            }
            if (game) {
                game.seat = null;
                if (other) send(game, encode(T.PEER_LEFT));
                game.close(1000, reason);
            }
        }
        broadcastStatus();
    }

    function onLobbyMessage(ws, raw) {
        if (!ws.rate(Date.now())) return ws.close(1008, 'rate limit');
        let msg;
        try {
            msg = JSON.parse(raw.toString());
        } catch {
            return;
        }
        if (msg && msg.t === 'join') join(ws, msg);
        else if (msg && msg.t === 'settings') updateSettings(ws, msg);
        else if (msg && msg.t === 'leave' && ws.seat) {
            log('leave', { role: ws.seat.role, nick: ws.seat.nick });
            resetRoom('PEER_LEFT', ws.seat);
        }
    }

    function join(ws, msg) {
        const now = Date.now();
        const error = (code) => send(ws, JSON.stringify({ t: 'error', code }));
        if (!ws.joinRate(now)) return error('RATE_LIMIT');
        if (ws.seat) return error('ALREADY_JOINED');
        const res = room.join(msg.nick, msg.password, now, msg.settings);
        if (!res.ok) {
            log('join_rejected', { code: res.code, ip: ws.ip });
            return error(res.code);
        }
        const { seat } = res;
        seat.lobby = ws;
        ws.seat = seat;
        log('join', { role: seat.role, nick: seat.nick, state: room.state });
        send(ws, JSON.stringify({ t: 'joined', role: seat.role, token: seat.token, settings: room.settings }));
        broadcastStatus();
    }

    function updateSettings(ws, msg) {
        const res = room.updateSettings(ws.seat, msg.settings);
        if (!res.ok) return send(ws, JSON.stringify({ t: 'error', code: res.code }));
        log('settings', { settings: room.settings });
        broadcastStatus();
    }

    function onGameFrame(ws, frame) {
        const now = Date.now();
        if (!ws.seat) return hello(ws, frame, now);
        const seat = ws.seat;
        room.touch(seat, now);
        if (frame.type === T.PING) return send(ws, encode(T.PING, frame.payload));
        if (frame.type === T.TICK_CTRL || frame.type === T.TICK_INPUT) return onTick(seat, frame);
        if (frame.type !== T.SESSION && frame.type !== T.INPUT) return;
        const peer = room.canForward() && room.peerOf(seat);
        if (!peer) return;
        const out = encode(frame.type, frame.payload);
        if (cfg.simDelayMs > 0) setTimeout(() => send(peer.game, out), cfg.simDelayMs);
        else send(peer.game, out);
    }

    /** Types 6/7: consumed by the ticker, never forwarded. Processing is delayed by SIM_DELAY_MS like the uplink. */
    function onTick(seat, frame) {
        const p = frame.payload;
        const isCtrl = frame.type === T.TICK_CTRL;
        if (p.length !== (isCtrl ? 5 : 6) || !room.ready) return;
        const a = isCtrl ? p.readUInt8(0) : p.readUInt32BE(0);
        const b = isCtrl ? p.readUInt32BE(1) : p.readInt16BE(4);
        const last = isCtrl ? 0 : a;
        later(() => {
            if (!room.seats.includes(seat) || !room.ready) return;
            if (isCtrl) ticker.ctrl(seat.role, a, b);
            else ticker.input(seat.role, b, last);
        });
    }

    function hello(ws, frame, now) {
        const claim = frame.type === T.HELLO && room.claim(frame.payload.toString('utf8'), now);
        if (!claim) return ws.close(1008, 'bad hello');
        const { seat } = claim;
        seat.game = ws;
        ws.seat = seat;
        clearTimeout(ws.helloTimer);
        log('claim', { role: seat.role, nick: seat.nick });
        send(ws, encode(T.HELLO, seat.role));
        if (claim.ready) {
            log('ready', { players: room.players });
            room.seats.forEach((s) => send(s.game, encode(T.PEER_READY)));
        }
    }

    function onGameMessage(ws, data, isBinary) {
        if (!isBinary) return ws.close(1003, 'binary only');
        let frames;
        try {
            frames = ws.parser.push(data);
        } catch {
            return ws.close(1009, 'frame too large');
        }
        for (const frame of frames) {
            if (ws.readyState !== OPEN) return;
            if (!ws.rate(Date.now())) return ws.close(1008, 'rate limit');
            onGameFrame(ws, frame);
        }
    }

    function onClose(ws) {
        const seat = ws.seat;
        if (seat) {
            log('leave', { role: seat.role, nick: seat.nick, via: ws.kind });
            resetRoom('PEER_LEFT', seat);
        }
    }

    lobbyWss.on('connection', (ws) => {
        ws.kind = 'lobby';
        ws.seat = null;
        ws.rate = rateLimiter(MAX_FRAMES_PER_SEC, 1000);
        ws.joinRate = rateLimiter(MAX_JOINS_PER_10S, 10000);
        lobbies.add(ws);
        ws.on('message', (raw) => onLobbyMessage(ws, raw));
        ws.on('close', () => {
            lobbies.delete(ws);
            onClose(ws);
        });
        send(ws, statusMsg());
    });

    gameWss.on('connection', (ws) => {
        ws.kind = 'game';
        ws.seat = null;
        ws.parser = new FrameParser(MAX_PAYLOAD);
        ws.rate = rateLimiter(MAX_FRAMES_PER_SEC, 1000);
        ws.helloTimer = setTimeout(() => ws.seat || ws.close(1008, 'hello timeout'), cfg.tokenTtlMs);
        ws.on('message', (data, isBinary) => onGameMessage(ws, data, isBinary));
        ws.on('close', () => {
            clearTimeout(ws.helloTimer);
            onClose(ws);
        });
    });

    [lobbyWss, gameWss].forEach((wss) =>
        wss.on('connection', (ws) => {
            ws.on('error', () => {});
        }),
    );

    function clientIp(req) {
        const fwd = cfg.trustProxy && req.headers['x-forwarded-for'];
        return fwd ? String(fwd).split(',')[0].trim() : req.socket.remoteAddress;
    }

    function reject(socket, status, text) {
        socket.write(`HTTP/1.1 ${status} ${text}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
        socket.destroy();
    }

    server.on('upgrade', (req, socket, head) => {
        const path = new URL(req.url, 'http://x').pathname;
        const wss = path === '/lobby' ? lobbyWss : path === '/game' ? gameWss : null;
        if (!wss) return reject(socket, 404, 'Not Found');
        if (cfg.allowedOrigins.length && !cfg.allowedOrigins.includes(req.headers.origin)) {
            log('reject', { why: 'origin', origin: req.headers.origin });
            return reject(socket, 403, 'Forbidden');
        }
        const ip = clientIp(req);
        const n = ipCounts.get(ip) || 0;
        if (n >= MAX_CONN_PER_IP) {
            log('reject', { why: 'ip_limit', ip });
            return reject(socket, 429, 'Too Many Requests');
        }
        wss.handleUpgrade(req, socket, head, (ws) => {
            ws.ip = ip;
            ipCounts.set(ip, n + 1);
            ws.on('close', () => {
                const left = (ipCounts.get(ip) || 1) - 1;
                if (left > 0) ipCounts.set(ip, left);
                else ipCounts.delete(ip);
            });
            wss.emit('connection', ws, req);
        });
    });

    const tickMs = Math.max(10, Math.min(1000, Math.floor(Math.min(cfg.idleTimeoutMs, cfg.tokenTtlMs) / 4)));
    const timer = setInterval(() => {
        const seat = room.findTimedOut(Date.now());
        if (seat) resetRoom('TIMEOUT', seat);
    }, tickMs);
    timer.unref();

    function listen(port = cfg.port) {
        return new Promise((resolve) => server.listen(port, () => resolve(server.address().port)));
    }

    function close() {
        clearInterval(timer);
        ticker.reset('shutdown');
        delayed.forEach(clearTimeout);
        delayed.clear();
        [...lobbyWss.clients, ...gameWss.clients].forEach((ws) => ws.terminate());
        return new Promise((resolve) => server.close(() => resolve()));
    }

    return { server, room, ticker, listen, close };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
    const relay = createRelay(configFromEnv());
    relay.listen().then((port) => log('listening', { port }));
    const stop = () => relay.close().then(() => process.exit(0));
    process.on('SIGTERM', stop);
    process.on('SIGINT', stop);
}
