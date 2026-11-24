# Web deployment checklist

Two parts: static site (`dist/web/`) and the WebSocket relay (`tools/relay/`).

## 1. Build the game

Produce `out/web/` (contains `bvn.swf` plus runtime asset folders) with the SHELL_Web build. `build-web` warns if `out/web/bvn.swf` is missing.

## 2. Bundle the site

```
RELAY_WS_BASE=wss://relay.example.com node tools/deploy/build-web.mjs --self-host-ruffle
```

- Output: `dist/web/` (git-ignored). Prints total size, 10 largest files, warns on files > 25 MB (Cloudflare Pages limit).
- `RELAY_WS_BASE` must be `wss://host[:port]` (no path); `--allow-insecure` permits `ws://` for tests.
- `--self-host-ruffle` runs `npm pack @ruffle-rs/ruffle@0.7.1` into `dist/web/ruffle-0.7.1/` and points `RUFFLE_URL` at it (no unpkg dependency). Needs `npm` and `tar` on PATH.
- Other flags: `--game <dir>` (default `out/web`), `--out <dir>` (default `dist/web`).

How runtime config works (`web/config.js`): `RELAY_WS_BASE` is `?relay=ws(s)://host` if present, else `ws://localhost:8080` on localhost / 127.0.0.1, else the value in generated `config.prod.js` (`window.BVN_PROD`). Local dev needs no edits; `web/config.prod.js` in git is an empty stub.

## 3. Deploy the relay

See `tools/relay/README.md` (Fly.io, Render, or VPS + Caddy). Set `ALLOWED_ORIGIN` to the static site origin, optionally `ROOM_PASSWORD`, and `TRUST_PROXY=1` behind a proxy. Run exactly one instance. Check `https://<relay>/health` returns `ok`.

## 4. Upload the static site

Upload `dist/web/` to Cloudflare Pages (`npx wrangler pages deploy dist/web`) or Netlify (publish dir `dist/web`). Both read `_headers` (wasm content type, no-cache for index/config, immutable cache for `ruffle-0.7.1/`). On hosts without `_headers` support, set equivalent headers manually, especially `Content-Type: application/wasm` for `*.wasm`. `bvn.swf` is cached 5 minutes with revalidation because its name is not versioned.

## 5. Smoke test

1. Open the site in tab A: room shows "Empty (0/2)"; join as host, game loads, "Waiting for opponent".
2. Tab B (or another device) opens the invite link and joins: both start the match.
3. Play a full match to the end: both return to the lobby with "Match finished".
4. While two players are in a match, a third tab shows "Room is full" and the Join button is disabled.
5. Close one player's tab mid-match: the other sees "Opponent left" and the room goes back to Empty.
6. Browser console has no CSP/CORS/mixed-content errors; `wss://` connections to `/lobby` and `/game` succeed.
7. Wrong origin test: `ALLOWED_ORIGIN` should block a page served from another origin.

## Manual leftovers

DNS/domain, relay secrets, choosing `ALLOWED_ORIGIN`, and the actual hosting accounts are not automated.
