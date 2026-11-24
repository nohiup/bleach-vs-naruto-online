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

### Fly.io

```
cd tools/relay
fly launch --no-deploy --copy-config      # uses fly.toml; pick your app name
# edit fly.toml: ALLOWED_ORIGIN = "https://<your static site>"
fly secrets set ROOM_PASSWORD=...         # optional
fly deploy
fly scale count 1                         # exactly one machine (room state is in memory)
```

`fly.toml` keeps one machine always running (`auto_stop_machines = "off"`, `min_machines_running = 1`) and health-checks `/health`. Fly terminates TLS, so the relay URL is `wss://<app>.fly.dev`; `TRUST_PROXY=1` is already set.

### Render (alternative)

`render.yaml` is a Blueprint for a Docker web service (paid plan: free instances sleep). Set `ALLOWED_ORIGIN` / `ROOM_PASSWORD` in the dashboard.

### Plain VPS (Docker + Caddy)

```
docker build -t bvn-relay .
docker run -d --name bvn-relay --restart unless-stopped -p 127.0.0.1:8080:8080 \
  -e ALLOWED_ORIGIN=https://your.site -e TRUST_PROXY=1 -e ROOM_PASSWORD=secret bvn-relay
```

Caddy (automatic HTTPS, WebSocket upgrade works without extra config) in `/etc/caddy/Caddyfile`:

```
relay.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

`sudo systemctl reload caddy`, then the relay URL is `wss://relay.example.com`. Point the DNS A/AAAA record at the VPS first.

### Settings to remember

- `ALLOWED_ORIGIN`: set to the exact origin(s) of the static site (`https://your.site`, no trailing slash); otherwise any site can use your relay.
- `ROOM_PASSWORD`: optional shared password players must enter in the lobby.
- `TRUST_PROXY=1`: required behind Fly/Caddy/any proxy so the per-IP limit uses the real client IP (otherwise all players share the proxy IP and hit the 5-connection limit).

Requirements for the host:
- Long-lived WebSocket support (put it behind TLS so pages on https can use `wss://`).
- Must not sleep or scale to zero on idle: room state is in memory, so run exactly one instance.
- Set `TRUST_PROXY=1` only when behind a trusted reverse proxy that sets `X-Forwarded-For`.
