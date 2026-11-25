# Browser performance optimization plan (Ruffle 0.7.1)

Status: research and plan only, no game code changed. Branch `perf-plan`, based on `feat/web-online` (f00c7ed0).
Scope: the browser build (`SHELL_Web` + `web/lobby.js`) running on Ruffle 0.7.1 (wgpu-webgl). Online 1v1 lockstep.
Paths are relative to the repo root. `K` = `CORE_KernelLogic/src/net/play5d/game/bvn`.

Evidence legend: "verified" = read in this repo. "unverified" = Ruffle behaviour from memory/docs that was not tested here and no web research was done. Treat unverified items as hypotheses to confirm with the measurement protocol (section 6).

## 0. Key findings (TL;DR)

1. **Logic and rendering share one clock.** One `ENTER_FRAME` = one lockstep logic step (`LockFrameServerLogic.render()` increments `_renderFrame` and applies one input frame, `K/ctrler/lan/LockFrameServerLogic.as:123-170`; the gate is `LockFrameLogic.render`, `K/ctrler/lan/LockFrameLogic.as:101-107`; `GameRender.render` runs on the same event, `K/ctrler/GameRender.as:195-260`). There is no frame skipping or decoupled interpolation. If Ruffle cannot finish a frame in 33 ms, the game itself runs slower than 30 logic steps/s (slow motion), and in lockstep the slower peer stalls the other. Every ms of render cost is therefore directly "lag".
2. **The web shell's effective frame rate in an online match is 30.** `LockFrameLogic.init` forces `GameConfig.FPS_GAME = 30` (`LockFrameLogic.as:93-96`) before `MainGame.enterGameStage` calls `setFPS(GameConfig.FPS_GAME)` (`K/MainGame.as:257-262`). No 2x render requirement at default settings.
3. **Latent hazard: the Web settings menu can set the stage to 60 FPS.** `GameInterfaceManager.applyConfig` (web) calls `MainGame.I.setFPS(60)` for MEDIUM/HIGH/HIGHER/BEST (`SHELL_Web/src/net/play5d/game/bvn/web/GameInterfaceManager.as:375-401`). If that runs while lockstep is active (`FPS_GAME == 30`), the stage ticks at 60 while logic assumes 30 per second: game speed doubles and desync/stall risk rises (`LANUtils.updateParams` scales by `FPS_GAME/30`, `K/ctrler/lan/LANUtils.as:61-65`). The same tiers request `StageQuality.HIGH_8X8` / `HIGH_16X16` (lines 377, 382), likely heavy MSAA in Ruffle (unverified mapping). The default is LOW (`SHELL_Web/src/WebLaunch.as:89`), so most users are on LOW/30 and **their lag is mostly real render cost, not a misconfigured FPS**.
4. **Probable biggest real costs (hypotheses; rank with profiling):** (a) per-frame fighter/effect display-list work with many vector MovieClips; (b) fighter glow via the `BitmapFilterView` path; (c) full-screen blend-mode effects (`ShineEffectView`, `BlackBackView`); (d) `BitmapData.draw` in `FightBar.updateBitmap`; (e) canvas resolution at devicePixelRatio; (f) MSAA from `stage.quality` / Ruffle `quality`; (g) no map layer cache on web (`afterBuildGame` is empty).
5. **Network stalls that look like lag are a separate problem**; section 5 shows how to tell them apart.

## 1. Frame-rate map (verified)

| Item | Value | Where |
|------|-------|-------|
| `GameConfig.FPS_GAME` default | 60 (var, rewritten by quality/lockstep) | `K/GameConfig.as:53` |
| `FPS_UI` / `FPS_ANIMATE` | 30 / 30 (const) | `GameConfig.as:55,57` |
| `FPS_SHINE_EFFECT` default | 15 | `GameConfig.as:59` |
| `GameConfig.setGameFps` | sets `FPS_GAME` | `GameConfig.as:158-159` (animate ratio `:155`) |
| `MainGame.setFPS` | sets `stage.frameRate` | `K/MainGame.as:163-167` |
| UI scenes | `setFPS(FPS_UI)` = 30 | `MainGame.as:183-372` |
| Game scene | `setFPS(FPS_GAME)` then `setQuality(QUALITY_GAME)` | `MainGame.as:261-262` |
| `ConfigVO.applyConfig` | LOW 30/shine 15; MEDIUM..BEST 60, shine 30/30/30/60; quality LOW/LOW/MEDIUM/HIGH/HIGH | `K/data/vos/ConfigVO.as:188-218` |
| Web `applyConfig` | LOW 30 (shine 10); MEDIUM 60 (shine 15); HIGH 60; HIGHER 60 + `HIGH_8X8`; BEST 60 + `HIGH_16X16` | `SHELL_Web/.../GameInterfaceManager.as:375-401` |
| Web default quality | `GameQuality.LOW` | `SHELL_Web/src/WebLaunch.as:89` |
| Lockstep override | `setGameFps(30)` on init, restore on dispose | `LockFrameLogic.as:84,96` |
| Animation gap | `_renderAnimateGap = ceil(FPS_GAME/FPS_ANIMATE) - 1` (0 at 30 FPS: timelines advance every frame) | `K/ctrler/game_ctrls/GameCtrl.as:160,869` |

Observations:
- At 30 FPS lockstep, `_renderAnimateGap == 0`: every fighter timeline advances every frame, so there is no spare frame to skip. 60 FPS would double the per-second work, so 60 must never be used in lockstep.
- Two quality tables disagree (`ConfigVO.applyConfig` vs web `applyConfig`, e.g. MEDIUM shine 30 vs 15). Pick one source of truth.
- `FPSDisplay` (`K/debug/FPSDisplay.as`) compares actual vs `stage.frameRate`; reuse it.

## 2. Hot-spot inventory (grep counts in `K/`, verified)

| Pattern | Count | Hottest / notable spots |
|---------|------:|-------------------------|
| `GlowFilter` | 27 | `fighter/ctrler/FighterEffectCtrl.as:53-57,238` (20px glow on fighters); `ui/select/*` (static, fine) |
| `BlurFilter` | 2 | `map/MapLayer.as:249` (applied once to a cached bitmap: OK) |
| `ColorMatrixFilter` | 2 | `ui/settings/KeyMapping.as:42` (settings only) |
| `DropShadowFilter` | 7 | `ui/Text.as:27` (every `Text`), `ui/fight/FighterHpBar.as:37,43` (HUD text) |
| `.filters =` | 22 refs | `fighter/FighterMain.as:136`, `ui/select/SelectPickMarkCtrl.as:215` |
| `BlendMode` | 63 | `views/effects/EffectView.as:35` (per effect), `ShineEffectView.as:86,89` (ADD/DARKEN full screen) |
| `cacheAsBitmap` | 12 | `ui/fight/FightFaceGroup.as:29-69`, `ui/fight/QiBar.as:236`, `stage/WorldMapStage.as:94-95`, `map/MapLayerCacheUtil.as` |
| `BitmapData` | 117 | |
| `.draw(` | 8 | `ui/fight/FightBar.as:344` (clear + draw per `updateBitmap`), `ctrler/effect/DisplayFrameBitmapCache.as:268,341` (cache fill), `map/MapLayer.as:360` |
| `new Dictionary` | 25 | `GameRender._entryMap` is lookup only; ordered Vector is iterated (good) |
| `for each` | 156 | e.g. `EffectCtrl.startFilter` linear scan, `ctrler/EffectCtrl.as:462` |
| `addChild` / `removeChild` | 233 / 73 | effects added/removed per hit (`EffectCtrl.as:263-268`, `shine` `:297-315`) |
| `new Point/Rectangle/Matrix` | 112 | `FightBar.updateBitmap` allocates two per call |
| `TextField` / `.text =` | 77 | HUD, `FPSDisplay`, `_delayText` in lockstep (`WebSessionCtrl.as:~508`) |

Mitigations already in code (do not redo): `DisplayFrameBitmapCache` (rasterizes effect/ghost frames, `K/ctrler/effect/DisplayFrameBitmapCache.as`); `BitmapFilterView` renders the glow into a cached bitmap rather than a live filter; `GameUI.BITMAP_UI = true` (`WebLaunch.as:87`); `ShineEffectView` uses an 80x60 bitmap scaled to 800x600 with a pool (`_manager.getShine()`); `GameRender` iterates an ordered Vector for determinism.

Specific concerns:
- `MapLayerCacheUtil.enableBitmapCache` uses `cacheAsBitmapMatrix` (AIR only; ReferenceError #1056 in Ruffle), so the web shell skips the whole utility (`SHELL_Web/.../GameInterfaceManager.as:320-326`). Maps get **no** bitmap cache on web, so large vector backgrounds are re-drawn every frame (Ruffle caches tessellation but still draws every path each frame; cost unverified).
- `ShineEffectView` full-screen `BlendMode.ADD/DARKEN` needs an extra render pass per active shine (blend modes in Ruffle require offscreen copy; cost unverified but typically among the most expensive features). Count is capped by `shineMaxCount` (`EffectCtrl.as:296`).
- `FightBar.updateBitmap` clears and redraws a vector UI into a bitmap whenever called (`ui/fight/FightBar.as:341-345`; callers `:200`, `:306`). Confirm the call frequency.
- Fighters are vector MCs with nested clips; count display objects (section 6).

## 3. Optimization plan

Order: quick wins (config) -> medium -> large. Each item: problem / evidence / change / expected gain / risk / effort / scope. Gains are rough guesses until measured.

### Tier A: quick wins (config level, no logic risk)

**A1. Lock the stage frame rate in lockstep (bug-class fix and guard).**
- Problem: web `applyConfig` can call `setFPS(60)` during lockstep (finding 3).
- Evidence: `GameInterfaceManager.as:375-401` vs `LockFrameLogic.as:93-96`.
- Change: in web `applyConfig`, skip `setFPS` / `FPS_SHINE_EFFECT` changes while `WebSessionCtrl.I.hostActive || clientActive`; make 30 the only online rate. Hide or neutralize FPS-raising tiers during a session.
- Gain: prevents 2x-speed/desync incidents that read as "lag"; none at default. Risk: low. Effort: S. Scope: web-only (`SHELL_Web`).

**A2. Cap `stage.quality` at LOW/MEDIUM; drop `HIGH_8X8` / `HIGH_16X16` in the web shell.**
- Problem: highest quality requests the largest MSAA sample count (unverified mapping); in wgpu-webgl MSAA costs fill-rate on every pass including each filter/blend pass.
- Evidence: `GameInterfaceManager.as:377,382`; default LOW at `WebLaunch.as:89` (only users who raised quality are hit).
- Change: map BEST/HIGHER -> `HIGH`, HIGH -> `MEDIUM`, MEDIUM/LOW -> `LOW`, or remove the choice online. Also set Ruffle `quality` (A4) consistently.
- Gain: roughly 10-40% frame time on fill-bound GPUs for users above LOW (unverified); none at LOW. Risk: low (softer image). Effort: S. Scope: web-only.

**A3. Ruffle renderer A/B: `wgpu-webgl` vs `webgpu` vs `webgl` vs `canvas`.**
- Problem: the default renderer is not guaranteed fastest; WebGPU may win where supported, canvas may win on weak iGPUs for simple scenes (unverified).
- Evidence: `web/lobby.js:262-269` passes no renderer option.
- Change: add `preferredRenderer` driven by a query-string override (`?renderer=...`) in `lobby.js`; default to the measured best. Confirm exact option/value names for 0.7.1 against Ruffle docs (unverified).
- Gain: potentially 1.2-2x on some GPUs. Risk: low (Ruffle falls back). Effort: S. Scope: web-only (`web/lobby.js`).

**A4. Explicit Ruffle player config.**
- Change in `player.load({...})` (`lobby.js:262`): `quality` ("low" or "medium"; default is "high", unverified), keep `letterbox: "on"`, `scale: "showAll"`, `forceScale: true`, raise `maxExecutionDuration` so heavy frames are not aborted, `logLevel: "error"` (lobby already filters `tag_utils.rs` spam in `quietRuffle`, a lower log level avoids the cost entirely), `splashScreen: false`, `contextMenu: "off"`. No known `frameRate` override in 0.7.1 (unverified; do not rely on it).
- Gain: small to medium. Risk: low. Effort: S. Scope: web-only.

**A5. Cap canvas size / devicePixelRatio; make the box 4:3.**
- Problem: the player box is up to 960x540 CSS px at 16:9 (`web/style.css:41`) around an 800x600 game. Ruffle renders at `devicePixelRatio`: a 2x-3x HiDPI screen gives a 1920x1080 to 2880x1620 backbuffer, 4-9x the pixels of 1x, with MSAA on top, plus letterbox bars that are still rendered.
- Change: (a) `.player-box` to `aspect-ratio: 4/3` and `max-width` around 800px; (b) a "Performance mode" that shrinks the CSS size and lets the browser upscale; (c) check whether 0.7.1 honours a pixel-ratio cap (unverified).
- Gain: large on HiDPI/4K laptops (2-4x fill reduction). Risk: low (blurrier). Effort: S. Scope: web-only (`web/style.css`, `lobby.js`).

### Tier B: medium (targeted code changes)

**B1. "Performance" toggle that disables the costliest visual-only features online.**
- Candidates by estimated cost: fighter glow (`FighterEffectCtrl.startGlow`, `FighterEffectCtrl.as:236-241`); screen shine (`EffectCtrl.shine`, `EffectCtrl.as:299`, already skipped when `FPS_SHINE_EFFECT == 0` at `:301`, so setting it to 0 online is a free switch); black-back/ghost effects (`EffectBlackBackHandler`); shake (`EffectShakeHandler`); slow-motion `bgBlur` (`EffectCtrl.as:287-289`).
- Constraint: visual-only; confirm no hit-stop frame counts depend on them (`freeze()` uses `FPS_GAME`, unaffected).
- Gain: medium, depends on skill frequency. Risk: low-medium. Effort: S-M. Scope: web flags plus small CORE gating.

**B2. Ruffle-safe map bitmap cache.**
- Problem: web skips `MapLayerCacheUtil` (AIR-only `cacheAsBitmapMatrix`).
- Evidence: `K/map/MapLayerCacheUtil.as:47-56`, `SHELL_Web/.../GameInterfaceManager.as:320-326`.
- Change: add a safe variant using plain `cacheAsBitmap = true` (already used for `bgLayer`) on layers without animated content (`mapLayer`, `frontFixLayer`), guarded by try/catch and a flag. Verify in Ruffle that cache survives camera translation (cached clips with scale/rotation changes rebuild; unverified). Do not cache animated layers.
- Gain: medium to large for maps with big static vectors; zero or negative with animated backgrounds. Risk: medium (seams, invalidation). Effort: M. Scope: CORE (`MapLayerCacheUtil`), called from web `afterBuildGame`.

**B3. Cheaper `FightBar.updateBitmap`.**
- Evidence: `ui/fight/FightBar.as:341-345` (copyPixels of an empty rect, then `draw`; allocates `Rectangle` and `Point` per call; callers `:200`, `:306`).
- Change: `fillRect`, hoist allocations, redraw only when HP/QI/state changed (dirty flag); measure call frequency first.
- Gain: small to medium. Risk: low. Effort: S. Scope: CORE.

**B4. Complete effect-cache warm-up before the match.**
- Evidence: `ctrler/WarmupCtrl.as:224-225` pre-instantiates filters only; first use of a skill effect rasterizes into `DisplayFrameBitmapCache` (`:268,341`) and spikes the frame.
- Change: pre-draw the selected fighters' effect frames during loading (see `.agents/warmup.md`).
- Gain: removes first-use spikes (stutter, not average FPS). Risk: low. Effort: M. Scope: CORE.

**B5. Trim per-frame allocations and display-list churn.**
- Targets: effect spawn/remove (`EffectCtrl.addEffect`/remove), `startFilter` linear search (`EffectCtrl.as:462`), `new Point/Rectangle/Matrix` inside `render`/`ENTER_FRAME` paths, pooling of `EffectView` (a pool exists for shine).
- Gain: modest (Ruffle allocs are cheap compared to Flash GC). Risk: medium (reuse bugs). Effort: M. Scope: CORE.

**B6. HUD text filters.** `ui/Text.as:27` applies `DropShadowFilter` to every `Text`; `FighterHpBar` does too (`:37,43`). Make sure the filter is applied once per bitmap, not on every text update, or use a pre-rendered outline. Gain: small to medium in fights with many number popups. Risk: low. Effort: S-M. Scope: CORE.

**B7. Lockstep debug text.** `_delayText` (`WebSessionCtrl.as` ~508) is a `TextField` updated by `LanClientSyncCore`; update at 2-4 Hz and only on change. Gain: small. Risk: none. Effort: S. Scope: web.

### Tier C: large refactors (only if A and B are not enough)

**C1. Decouple render from logic (skip drawing, not logic, under load).** Today a slow frame slows the whole game (finding 1). Allowing logic catch-up steps without display updates keeps game speed correct and sacrifices only smoothness. Needs `GameRender` split into logic functions and display updates (not split today), while keeping the lockstep schedule deterministic. Gain: large perceived. Risk: high. Effort: L. Scope: CORE.

**C2. Pre-rasterize fighters (sprite sheets).** Extend the `DisplayFrameBitmapCache` idea to fighter timelines at load time. Biggest win for vector-heavy characters (draw becomes blit), costs memory and may break code that reads live timeline state/hit boxes. Gain: large. Risk: high. Effort: L. Scope: CORE plus `packs`.

**C3. Asset diet** (section 4.2): simplify heavy character vectors, subset fonts. Effort: L (art side).

**C4. Upgrade Ruffle** (section 4.1). Effort: M, requires online regression. Scope: web-only.

**C5. Batch small effects into one `BitmapData` layer** if display-object counts prove the effect layer is a bottleneck. Gain: depends on counts. Risk: high. Effort: L. Scope: CORE.

## 4. Ruffle options and assets

### 4.1 Ruffle version and options (mostly unverified; check docs for the pinned version)
- Pinned `@ruffle-rs/ruffle@0.7.1` (`web/README.md`, `RUFFLE_URL` in `web/config.js`). Current config at `web/lobby.js:262-269` sets only `url, autoplay, letterbox, allowScriptAccess, socketProxy, parameters`.
- Worth testing: `preferredRenderer`, `quality`, `scale`/`forceScale`, `maxExecutionDuration`, `logLevel`, `splashScreen`, `contextMenu`.
- Newer Ruffle versions: rendering and AVM2 performance have generally improved release to release (unverified; no web research was done here). Action: use `RUFFLE_URL` to load the 2-3 newest tagged versions and run the same scripted match (section 6). Watch for AVM2 behaviour differences that affect lockstep (Math/random, timers, `getTimer`), so any upgrade needs a two-client desync soak test.
- Browser side: confirm hardware acceleration (`chrome://gpu`); hide or pause lobby DOM animations/chat while `player` exists so they do not compete for the main thread.

### 4.2 Assets (sizes as reported by the owner; asset binaries are not in this worktree, so unverified here)
- **Font SWFs** (`microsoft_jhenghei`, `yahei`, `malgun`, 4-7.5 MB each) come from `font_dir` in `shared/assets/assets/config/language.json:2`, and `LanguageStage.loadConfigBack` (`K/stage/LanguageStage.as:163-185`) does not preload them ("进页不预载字体 SWF"); only the selected language is fetched. They are a **download/parse cost, not a per-frame cost**. Actions: serve with gzip/brotli (check `web/_headers`), fetch only the chosen font, consider glyph subsetting (5-10x smaller). Gain: load time, no FPS gain expected. Effort: M. Scope: assets/tools.
- **effect.swf 3.9 MB** (`AssetManager._effectSwfPath`, `K/ctrler/AssetManager.as:41`): load-time cost; per-frame cost depends on the clips (partially absorbed by `DisplayFrameBitmapCache`).
- **Per-character SWFs**: inspect with JPEXS for shapes with thousands of path points, gradient fills, hairline strokes, nested masks, timeline filters. Deliver a table (character, shape count, max path points, filter/mask count). Scope: assets/tools.
- The embedded UI SWFs (`CORE_Utils/.../SwfLib.as:40-72`) are parsed at start: startup time only.

## 5. Real render cost vs lockstep stalls

Both look like "choppy" because logic and render share a clock (finding 1).

| Symptom | Render-bound | Network/lockstep-bound |
|---------|--------------|------------------------|
| FPS overlay (`FPSDisplay`: actual/target, frame ms) | actual < 30, frame ms > 33 steadily or in bursts around effects; also in menus/heavy maps | actual = 30, frame ms ~33, but gameplay freezes in bursts |
| Offline/local match | also laggy | smooth |
| Stall callbacks | none | `LanStallMonitor.onStall(ms)` fires (`WebSessionCtrl.as:~589`); `WebBridge.emit('stall', {ms})` reaches the lobby |
| Scene dependence | worse with many effects, specific maps/fighters | independent of scene, correlates with ping/jitter |
| `inputDelay` setting | no effect | higher delay reduces freezes and adds latency |
| `renderHost/renderClient` returning false | rare | frequent (`WebSessionCtrl.as:553-571`; `LockFrameServerLogic.as:136,154`) |
| Who is affected | each machine by its own load | both players; the peer with the worse link stalls both |

Procedure: (1) run the same fight offline and online; if offline is also slow it is render cost. (2) Add a per-second `stall%` (frames where `renderHost/renderClient` returned false / total) to the FPS overlay. (3) Compare `getTimer()` deltas: stall frames are short (early return), render-bound frames are long.

## 6. Measurement protocol

Hardware: at least one integrated-GPU laptop (likely complainant), one discrete-GPU desktop, one HiDPI (devicePixelRatio >= 2) display. Browser: current Chrome plus a Firefox/Safari spot check. Record Ruffle version, renderer, devicePixelRatio, canvas size, `stage.quality`.

1. **Baseline scenario:** same two fighters, same map, 60 s with a fixed input pattern including 3-4 big skills/ultimates; offline vs CPU first, then online on a good network. Three runs, report the median.
2. **Overlay:** enable the in-game FPS overlay (parallel work item): actual FPS, frame ms (avg, p95, p99), and the stall counter from section 5.
3. **Chrome DevTools Performance:** record 10 s of a skill-heavy moment. Look at main-thread long tasks, Ruffle wasm self time, the GPU lane, rAF cadence, dropped frames. High wasm time = AVM2/display-list/tessellation (CPU); low wasm with high GPU/raster = fill-rate, MSAA, filters, blends.
4. **`chrome://gpu`:** confirm hardware acceleration and WebGL2/WebGPU availability.
5. **Ruffle diagnostics:** `logLevel: "debug"` and the player context-menu diagnostics if present (`?ruffle_debug` style flags are unverified for 0.7.1).
6. **Display-object count:** in a debug build, recursively count `numChildren` for the game layer, effect layer and map layers at fixed times; find the layer with thousands of nodes.
7. **A/B toggles** (one at a time, same scenario): `stage.quality` LOW/MEDIUM/HIGH; `FPS_SHINE_EFFECT = 0`; fighter glow off; map cache on/off (B2); `preferredRenderer`; canvas size 800x600 vs 960x540 vs 1920x1080; devicePixelRatio forced to 1; lobby DOM hidden during play. Record avg FPS and p95 frame ms.
8. **Acceptance:** stable 30 FPS (p95 frame time < 33 ms) on the integrated-GPU reference machine at default settings, and online stall frames < 1% at 50 ms RTT.

## 7. Recommended order

1. A1, A5, A4, A2, A3 (config-level, web-only).
2. Run the measurement protocol, then pick from B1 (`FPS_SHINE_EFFECT = 0` is nearly free), B2, B3/B6/B7, B4.
3. Only then C1, C2, C4.

## 8. Do not do

- Do not run lockstep at 60 FPS "for smoothness": logic is one step per frame, so it doubles speed or desyncs (`LANUtils.as:61-65`, `LockFrameLogic.as:93-96`).
- Do not use `cacheAsBitmapMatrix` or any AIR-only API (`kyo.air.*`) in the web shell: ReferenceError #1056 in Ruffle (`GameInterfaceManager.as:320-326`).
- Do not enable `cacheAsBitmap` on layers with animated content or per-frame transforms: it invalidates every frame and costs more than it saves.
- Do not add live `filters` on fighters/effects; keep the bitmap-cache path (`BitmapFilterView`, `DisplayFrameBitmapCache`).
- Do not make logic depend on render-quality flags in ways that change hit-stop or frame counts: peers with different settings must stay in lockstep. Visual-only toggles are fine.
- Do not change `GameRender`'s ordered-Vector iteration to `Dictionary` iteration (`GameRender.as`, determinism).
- Do not upgrade Ruffle without a two-client desync soak test.
- Do not subset or remove font glyphs without checking every language pack.
