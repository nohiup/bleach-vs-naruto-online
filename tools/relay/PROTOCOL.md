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
- `{"t":"status","state":"EMPTY"|"WAITING"|"PLAYING","players":["nick", ...],"settings":{...}|null}` on connect and on every change; `settings` is the room settings while WAITING/PLAYING, `null` when EMPTY
- `{"t":"joined","role":"host"|"client","token":"<hex 32>","settings":{...}}` seat granted; `settings` = current room settings
- `{"t":"error","code":"ROOM_FULL"|"BAD_NICK"|"BAD_PASSWORD"|"RATE_LIMIT"|"ALREADY_JOINED"|"NOT_HOST"|"SETTINGS_LOCKED"}`
- `{"t":"reset","reason":"PEER_LEFT"|"TIMEOUT"}` room was reset while you held a seat

client -> server
- `{"t":"join","nick":"...","password":"...","settings":{...}}` (`password` only checked if env `ROOM_PASSWORD` set; `settings` optional, used only if this join becomes the host, ignored for the client)
- `{"t":"settings","settings":{...}}` host changes room settings; only from the lobby socket holding the host seat and only while WAITING, else `error` `NOT_HOST` (not the host / no seat) or `SETTINGS_LOCKED` (state PLAYING). On success a `status` is broadcast.
- `{"t":"leave"}`

Rules
- First join = `host`, second = `client`, further -> `ROOM_FULL`.
- Room settings (chosen by the host): `{"hp":<num>,"time":<int>,"inputDelay":<int>}`; `hp` in {0.5,1,2,3,5} (default 1), `time` in {30,60,90,-1} (-1 = unlimited, default 60), `inputDelay` integer 1..6 (default 3). Invalid or missing fields silently fall back to the default (a join is never rejected for bad settings). Settings reset to `null` when the room resets.
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

### Relay-paced fight frames (symmetric netcode)

During a fight the RELAY is the clock. Both SWFs are equal clients: neither waits for the
other; each plays the relay's frame stream from a jitter buffer. All integers big-endian.

| type | name       | direction    | payload |
|------|------------|--------------|---------|
| 6    | TICK_CTRL  | swf -> relay | `[u8 cmd][u32 epoch]` — cmd 1 = START, 2 = STOP |
| 7    | TICK_INPUT | swf -> relay | `[u32 lastFrame][i16 k]` — sender's latest local input bitmask `k` and the last frame it has simulated |
| 8    | TICK_FRAME | relay -> swf | `[u32 startFrame][u8 count]` then `count` × `[i16 p1K][i16 p2K]` for frames `startFrame .. startFrame+count-1` |

Relay rules (per room):
- `epoch` identifies one fight segment (one round). Both SWFs use the same sequence 1, 2, 3, …
  (reset to 1 when a new match starts on the select screen → the SWF simply counts rounds of the
  current match; START with an epoch <= the running one is ignored).
- Ticking starts only when BOTH seats sent START with the same epoch. Then: frame counter = 0,
  latest k of both seats = 0, and every 1000/30 ms (drift-free schedule based on a monotonic
  clock; if the timer fires late, emit all due frames at once) the relay creates frame N+1 with
  `p1K` = latest TICK_INPUT k of the HOST seat and `p2K` = latest k of the CLIENT seat.
- After creating frames, the relay sends ONE TICK_FRAME to both seats containing the newest
  frames, always repeating the last 4 frames for redundancy (count ≤ 8 normally; ≤ 64 if
  catching up after a late timer).
- STOP (either seat) or a START with a higher epoch from one seat stops ticking (no more frames)
  until both seats START the next epoch. Peer leave / room reset also stops ticking.
- TICK_INPUT received while not ticking just updates the stored latest k.
- Types 6/7 are NOT forwarded to the other seat. Types 1/2 forwarding is unchanged.
- Rate: each SWF sends ≤ 30 TICK_INPUT/s + ping; relay sends 30 TICK_FRAME/s to each seat.

SWF rules:
- Each SWF sends TICK_INPUT once per local tick while a fight segment is active.
- Frame N is simulated only after frame N arrived; both peers apply exactly `p1K` to P1 and
  `p2K` to P2 for frame N → identical simulation. Local input reaches the screen after
  ~RTT(to relay) + buffer, equally for both players.
- Select screen, settings, round/game finish SYNC and snapshots keep using SESSION (type 1)
  messages exactly as today; finish/snapshot messages carry the relay frame number and are
  applied when the receiver reaches that frame.

AS3 contract (CORE ↔ SHELL_Web):
- `CORE_Shared/.../interfaces/lan/ILanRelayLockLink.as`:
  `function sendTickCtrl(cmd:int, epoch:uint):void;` and `function sendTickInput(lastFrame:uint, k:int):void;`
- `CORE_Shared/.../data/lan/LanRelayTick.as`: constants `CMD_START = 1`, `CMD_STOP = 2`,
  `FRAME_TYPE_CTRL = 6`, `FRAME_TYPE_INPUT = 7`, `FRAME_TYPE_FRAME = 8`.
- `LanNetConfig.relayPaced:Boolean` (default false). When true, SHELL_Web creates
  `LockFrameRelayLogic` (CORE_KernelLogic, ctrler/lan) on BOTH peers instead of
  LockFrameServerLogic/LockFrameClientLogic for the fight:
  `init(link:ILanRelayLockLink, localInput:GameSocketInput, inputP1:GameSocketInput, inputP2:GameSocketInput, localIsP1:Boolean)`,
  `render():Boolean` (called by LockFrameLogic each ENTER_FRAME), `receiveTickFrame(payload:ByteArray):void`
  (payload = TICK_FRAME payload without the 3-byte frame header), `stallMonitor`, `frame:uint`,
  `bufferedFrames:int`, `dispose()`.

## SWF <-> page

FlashVars passed by the page: `web=1`, `role`, `token`, `nick`, `relayHost=bvn-game`, `relayPort=17511`.
Optional: `showFps` (`1` = start with the FPS overlay visible, default hidden), `mode` (`team` | `single`, default `single`), `inputDelay` (int 1-6, default 3; clamped; only the host's value is used, it is synced to the client at game start), `hp` (number, one of `0.5`, `1`, `2`, `3`, `5`, default `1`) and `time` (int seconds, one of `30`, `60`, `90`, `-1` = unlimited, default `60`); invalid values fall back to the default; only the host's `hp`/`time` are used.

Session message (SESSION frame, JSON) host -> client, sent before the host's `WEB_READY`: `{"type":"WEB_SETTINGS","hp":<num>,"time":<int>,"inputDelay":<int>}`. The client validates `hp`/`time` against the same sets (invalid -> default); it ignores `inputDelay` for gameplay (it receives the real delay via SYNC GAME_START) and only echoes it in `matchSettings`, applies them to its game config, and does not start the match until it has received it. Both sides apply `hp`/`time` before entering character select, re-apply them every time character select, loading or the match stage is entered again (so every rematch in the same session uses the host's settings), and restore the player's own offline values only when the session really ends (leave, disconnect, peer left, back to main menu); nothing is saved to local storage while overridden.

Rematch: after a normal match end the SWF emits `matchEnd` and the game returns to character select through its normal LAN flow; the relay connection and the session stay open. The lobby keeps both players in the room, shows a brief "Match finished - next match" notice and a win counter "Host N - M Client" in the top bar (reset when a new session starts). Only "Leave match" / `bvnLeave` (or a disconnect) ends the session.

SWF calls `window.bvnOnEvent(name, json)` via `ExternalInterface` (`json` is a JSON string):

| name | payload | meaning |
|------|---------|---------|
| `connected` | `{"role":"host"\|"client","nick":"..."}` | relay HELLO accepted |
| `peerReady` | `{}` | both seats claimed |
| `matchSettings` | `{"hp":num,"time":int,"inputDelay":int}` | effective life ratio, round time and input delay applied for this match (both peers, emitted right before character select, before `matchStart`) |
| `matchStart` | `{"role":"host"\|"client"}` | a match began |
| `matchEnd` | `{"winner":"host"\|"client"}` or `{}` | one match finished normally (winner omitted if unknown); NOT a disconnect and the session stays open: the game returns to character select for a rematch with the same settings, and the page should only update its UI (e.g. win counter, "Match finished - next match") |
| `stall` | `{"ms":int}` | waiting for the peer's input for `ms` ms (emitted after 500 ms, at most every 250 ms, only once a round has started) |
| `resume` | `{"ms":int}` | the stall that was reported ended after `ms` ms |
| `desync` | `{"round":int,"p1":[local,remote],"p2":[local,remote]}` | HP mismatch vs host at round sync (client only); match continues |
| `disconnected` | `{"reason":"peer_left"\|"socket_close"\|"stall_timeout"\|"sync_error"\|"leave"}` | the session ended (failure, `bvnLeave`, or a player backing out to the game's main menu, reported as `leave`); `stall_timeout` = 10 s stall during a round |
| `ping` | `{"rtt":ms}` | relay round trip |
| `error` | `{"msg":"..."}` | non-fatal error |

Page may call SWF callback `bvnLeave()` (registered with `ExternalInterface.addCallback`); it ends the session and emits `disconnected {"reason":"leave"}`.

Page may call SWF callback `bvnToggleFps([show])` (registered with `ExternalInterface.addCallback`) to show/hide the FPS overlay (small semi-transparent box, top-right: render FPS measured from `ENTER_FRAME` and refreshed twice a second, stage `frameRate`, game logic FPS); no argument toggles, a boolean sets it. The same overlay toggles with the `F3` key inside the SWF. The lobby remembers its "Show FPS" checkbox in `localStorage` (`bvn.fps`) and passes `showFps=1` at start.

Host page may call SWF callback `bvnSetSettings(json)` (registered with `ExternalInterface.addCallback`) with `{"hp":num,"time":int,"inputDelay":int}` (fields optional). Each field is validated like the FlashVars (`hp` in 0.5/1/2/3/5, `time` in 30/60/90/-1, `inputDelay` int 1-6); an invalid field keeps its current value (FlashVars initial values, overridden by earlier calls). It is accepted only on the host and only until the host has sent `WEB_SETTINGS` (i.e. before the match starts); otherwise it is ignored (logged to the console). The values current at `WEB_SETTINGS` send time are the ones used for the match.
