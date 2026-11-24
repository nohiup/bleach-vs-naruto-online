# BvN relay

Single-room (2 seats) WebSocket relay for the browser port. Protocol: see [PROTOCOL.md](PROTOCOL.md).

Endpoints: `GET /health` (`ok`), `WS /lobby` (JSON), `WS /game` (binary frames).

## Run locally

```
cd tools/relay
npm install
npm start          # listens on :8080
npm test
```

## Environment

| Var | Default | Meaning |
|-----|---------|---------|
| `PORT` | 8080 | listen port |
| `ALLOWED_ORIGIN` | unset | comma list of allowed `Origin`s; unset = allow all (warning logged) |
| `ROOM_PASSWORD` | unset | if set, `join` must carry the same `password` |
| `TOKEN_TTL_MS` | 15000 | time to claim a seat token via `/game` HELLO |
| `IDLE_TIMEOUT_MS` | 10000 | seat timeout without any frame after HELLO |
| `TRUST_PROXY` | unset | `1` = use first `X-Forwarded-For` entry as client IP |

Limits: payload <= 4096 bytes, <= 120 frames/s per connection, <= 5 connections per IP.

## Deploy

```
docker build -t bvn-relay .
docker run -p 8080:8080 -e ALLOWED_ORIGIN=https://your.site -e TRUST_PROXY=1 bvn-relay
```

Requirements for the host:
- Long-lived WebSocket support (put it behind TLS so pages on https can use `wss://`).
- Must not sleep or scale to zero on idle: room state is in memory, so run exactly one instance.
- Set `TRUST_PROXY=1` only when behind a trusted reverse proxy that sets `X-Forwarded-For`.
