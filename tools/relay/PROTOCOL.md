# BvN Web Online Protocol (single room, 2 seats)

Shared contract between the relay (`tools/relay/`), the lobby page (`web/`) and the
browser shell (`SHELL_Web`). Change all three together.

## Topology

- Static site serves `web/index.html` (lobby), Ruffle, `bvn.swf`, assets.
- Relay (Node.js, `ws`) exposes:
  - `GET /health` -> `200 ok`
  - `WS /lobby` -> JSON text frames (lobby page)
  - `WS /game`  -> binary frames (SWF through Ruffle `socketProxy`)
- Ruffle config on the page:
  `socketProxy: [{ host: "bvn-game", port: 17511, proxyUrl: "<relayWsBase>/game" }]`
  The SWF always connects to `bvn-game:17511` in web mode.

## Lobby (`/lobby`, JSON)

server -> client
- `{"t":"status","state":"EMPTY"|"WAITING"|"PLAYING","players":["nick", ...]}` on connect and on every change
- `{"t":"joined","role":"host"|"client","token":"<hex 32>"}` seat granted
- `{"t":"error","code":"ROOM_FULL"|"BAD_NICK"|"BAD_PASSWORD"|"RATE_LIMIT"|"ALREADY_JOINED"}`
- `{"t":"reset","reason":"PEER_LEFT"|"TIMEOUT"}` room was reset while you held a seat

client -> server
- `{"t":"join","nick":"...","password":"..."}` (`password` only checked if env `ROOM_PASSWORD` set)
- `{"t":"leave"}`

Rules
- First join = `host`, second = `client`, further -> `ROOM_FULL`.
- Nick: 1-16 chars, `[A-Za-z0-9 _-]`.
- Token must be claimed by a `/game` HELLO within 15 s, else seat freed.
- State: EMPTY (0 seated) -> WAITING (host seated) -> PLAYING (both seated).
  Any seat leaving / disconnecting / timing out resets the whole room to EMPTY.
- Closing the lobby socket of a seated player also frees the room.

## Game (`/game`, binary)

Every frame: `[u8 type][u16 length BE][payload (length bytes)]`.
One WebSocket binary message may carry one or more frames; a frame may also be split
across messages (treat it as a byte stream — Ruffle delivers a TCP-like stream).

| type | name        | direction        | payload |
|------|-------------|------------------|---------|
| 0    | HELLO       | swf -> relay     | UTF-8 token |
| 0    | HELLO_OK    | relay -> swf     | UTF-8 role (`host`/`client`) |
| 1    | SESSION     | swf <-> swf      | opaque (TCP-equivalent LAN messages) |
| 2    | INPUT       | swf <-> swf      | opaque (UDP-equivalent lockstep input) |
| 3    | PING        | swf -> relay     | opaque; relay echoes same frame back to sender |
| 4    | PEER_LEFT   | relay -> swf     | empty; then relay closes socket |
| 5    | PEER_READY  | relay -> swf     | empty; sent to both when both seats claimed |

- Relay forwards types 1 and 2 unchanged to the other seat; drops them before PEER_READY.
- No PING (or any frame) for 10 s -> seat timeout -> room reset.
- Limits: frame payload <= 4096 bytes, <= 120 frames/s per connection, <= 5 connections per IP.
- Bad HELLO token -> close socket.

## SWF <-> page

FlashVars passed by the page: `web=1`, `role`, `token`, `nick`, `relayHost=bvn-game`, `relayPort=17511`.

SWF calls `window.bvnOnEvent(name, json)` via `ExternalInterface` with names:
`connected`, `peerReady`, `matchStart`, `matchEnd`, `disconnected`, `ping` (`{"rtt":ms}`), `error` (`{"msg":...}`).

Page may call SWF callback `bvnLeave()` (registered with `ExternalInterface.addCallback`).
