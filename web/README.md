# BvN web lobby

Static lobby page that hosts the Flash game in Ruffle and talks to the relay (see `tools/relay/PROTOCOL.md`).

- `config.js`: `RELAY_WS_BASE` (e.g. `ws://localhost:8080`, use `wss://` in production), `SWF_URL`, `RUFFLE_URL` (pinned `@ruffle-rs/ruffle@0.7.1`).
- Local test: start the relay, then `node web/dev-server.mjs --assets <dir containing bvn.swf and game assets>` and open http://localhost:5173.
- Invite link is the current page URL.
- Controls hint text is a placeholder in `index.html`.
