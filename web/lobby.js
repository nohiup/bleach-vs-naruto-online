(function () {
    "use strict";
    var cfg = window.BVN_CONFIG || {};
    var RELAY = cfg.RELAY_WS_BASE || "ws://localhost:8080";
    var SWF_URL = cfg.SWF_URL || "bvn.swf";
    var RUFFLE_URL = cfg.RUFFLE_URL;
    var BACKOFF = [1000, 2000, 5000];
    var NICK_RE = /^[A-Za-z0-9 _-]{1,16}$/;
    var ERRORS = {
        ROOM_FULL: "Room is full.",
        BAD_NICK: "Invalid nickname (1-16 letters, digits, space, _ or -).",
        BAD_PASSWORD: "Wrong room password.",
        RATE_LIMIT: "Too many attempts, please wait a moment.",
        ALREADY_JOINED: "You already joined this room.",
        NOT_HOST: "Only the host can change room settings.",
        SETTINGS_LOCKED: "Settings are locked: the match has started."
    };
    var HP_OPTS = ["0.5", "1", "2", "3", "5"];
    var TIME_OPTS = ["30", "60", "90", "-1"];
    var $ = function (id) { return document.getElementById(id); };
    var screens = ["lobby", "game", "ended"];
    var ws = null;
    var retry = 0;
    var retryTimer = null;
    var online = false;
    var room = { state: "EMPTY", players: [], settings: null };
    var seat = null;
    var joining = false;
    var player = null;
    var ruffleLoading = null;
    var desyncTimer = null;
    var REASONS = { peer_left: "Opponent left", socket_close: "Connection lost", stall_timeout: "Opponent not responding", leave: "You left" };
    // QUIET_RUFFLE_LOG: drop Ruffle's harmless "tag_utils.rs" lines (thousands of them); all other output is kept
    function quietRuffle() {
        if (cfg.QUIET_RUFFLE_LOG === false || quietRuffle.done) return;
        quietRuffle.done = true;
        ["log", "error", "warn", "info"].forEach(function (k) {
            var orig = console[k];
            console[k] = function () {
                for (var i = 0; i < arguments.length; i++) {
                    if (typeof arguments[i] === "string" && arguments[i].indexOf("tag_utils.rs") !== -1) return;
                }
                return orig.apply(console, arguments);
            };
        });
    }
    function hideStall() { $("stall").classList.add("hidden"); }
    function hideDesync() { clearTimeout(desyncTimer); $("desync").classList.add("hidden"); }
    function showScreen(name) {
        screens.forEach(function (s) { $("screen-" + s).classList.toggle("hidden", s !== name); });
    }
    function setMsg(text) { $("msg").textContent = text || ""; }
    function storeGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
    function storeSet(k, v) { try { localStorage.setItem(k, v); } catch (e) { } }
    // own saved preferences (never overwritten by the host's values shown to a joiner)
    function prefs() {
        var d = parseInt(storeGet("bvn.delay"), 10), hp = storeGet("bvn.hp"), t = storeGet("bvn.time");
        return {
            hp: Number(HP_OPTS.indexOf(hp) >= 0 ? hp : "1"),
            time: parseInt(TIME_OPTS.indexOf(t) >= 0 ? t : "60", 10),
            inputDelay: d >= 1 && d <= 6 ? d : 3
        };
    }
    function savePrefs(s) {
        storeSet("bvn.delay", String(s.inputDelay));
        storeSet("bvn.hp", String(s.hp));
        storeSet("bvn.time", String(s.time));
    }
    function readSel(p) {
        var d = parseInt($(p + "delay").value, 10), hp = $(p + "hp").value, t = $(p + "time").value;
        return {
            hp: Number(HP_OPTS.indexOf(hp) >= 0 ? hp : "1"),
            time: parseInt(TIME_OPTS.indexOf(t) >= 0 ? t : "60", 10),
            inputDelay: d >= 1 && d <= 6 ? d : 3
        };
    }
    function writeSel(p, s) {
        $(p + "delay").value = String(s.inputDelay);
        $(p + "hp").value = String(s.hp);
        $(p + "time").value = String(s.time);
    }
    function cleanSettings(s) {
        if (!s || typeof s !== "object") return null;
        var hp = Number(s.hp), t = parseInt(s.time, 10), d = parseInt(s.inputDelay, 10);
        if (HP_OPTS.indexOf(String(hp)) < 0 || TIME_OPTS.indexOf(String(t)) < 0 || !(d >= 1 && d <= 6)) return null;
        return { hp: hp, time: t, inputDelay: d };
    }
    function fmtSettings(s) {
        return "Life " + Math.round(s.hp * 100) + "% \u00b7 Time " + (s.time < 0 ? "\u221e" : s.time + "s") + " \u00b7 Delay " + s.inputDelay;
    }
    // lobby selects: editable (own prefs) when room is empty, else read-only copy of the host's settings
    function renderSettings() {
        var ro = !seat && online && room.state !== "EMPTY" && !!room.settings;
        ["delay", "hp", "time"].forEach(function (k) { $(k).disabled = ro; });
        writeSel("", ro ? room.settings : prefs());
        $("hs-legend").textContent = ro ? "Set by host (read-only)" : "Host settings";
        $("hs-help").textContent = ro ? "The room host chose these settings." : "Applied when you create the room (first to join). The opponent uses your settings.";
        if (!seat) return;
        var rs = room.settings || seat.settings;
        var edit = seat.role === "host" && !seat.locked && room.state !== "PLAYING";
        $("ov-settings").classList.toggle("hidden", !edit);
        if (edit && room.settings && !seat.dirty) writeSel("ov-", room.settings);
        var showRo = !edit && !!rs;
        $("roomset").textContent = showRo ? "Room: " + fmtSettings(rs) : "";
        $("roomset").classList.toggle("hidden", !showRo || !$("match").classList.contains("hidden"));
        $("ov-readonly").textContent = !edit && rs ? "Set by host (read-only): " + fmtSettings(rs) : "";
        $("ov-readonly").classList.toggle("hidden", edit || !rs);
        ["delay", "hp", "time"].forEach(function (k) { $("ov-" + k).disabled = !edit; });
    }
    function lockSettings() {
        if (!seat || seat.locked) return;
        seat.locked = true;
        renderSettings();
    }
    function onHostChange() {
        if (!seat || seat.role !== "host" || seat.locked || room.state === "PLAYING") return;
        var s = readSel("ov-");
        savePrefs(s);
        seat.settings = s;
        seat.dirty = true;
        $("ov-msg").textContent = "";
        send({ t: "settings", settings: s });
        try { if (player && typeof player.bvnSetSettings === "function") player.bvnSetSettings(JSON.stringify(s)); } catch (e) { }
    }
    function renderRoom() {
        var st = $("room-status"), pl = $("room-players"), btn = $("btn-join"), dot = $("dot");
        dot.className = "dot" + (online ? (room.state === "EMPTY" ? " on" : " wait") : "");
        pl.textContent = "";
        renderSettings();
        if (!online) {
            st.textContent = "Server offline";
            btn.textContent = "Join";
            btn.disabled = true;
            return;
        }
        if (room.state === "PLAYING") {
            st.textContent = "In match (2/2)";
            pl.textContent = room.players.join(" vs ");
            btn.textContent = "Room is full";
            btn.disabled = true;
        } else if (room.state === "WAITING") {
            st.textContent = "Waiting for opponent (1/2)";
            pl.textContent = "Host: " + (room.players[0] || "?");
            btn.textContent = "Join";
            btn.disabled = joining || !!seat;
        } else {
            st.textContent = "Empty (0/2)";
            btn.textContent = "Join";
            btn.disabled = joining || !!seat;
        }
    }
    function connect() {
        clearTimeout(retryTimer);
        var sock;
        try { sock = new WebSocket(RELAY + "/lobby"); } catch (e) { scheduleRetry(); return; }
        ws = sock;
        sock.onopen = function () { retry = 0; online = true; renderRoom(); };
        sock.onmessage = function (ev) {
            var m;
            try { m = JSON.parse(ev.data); } catch (e) { return; }
            onLobbyMessage(m);
        };
        sock.onclose = function () {
            if (ws !== sock) return;
            ws = null;
            online = false;
            joining = false;
            if (seat) endGame("Connection lost");
            renderRoom();
            scheduleRetry();
        };
        sock.onerror = function () { };
    }
    function scheduleRetry() {
        var d = BACKOFF[Math.min(retry, BACKOFF.length - 1)];
        retry++;
        retryTimer = setTimeout(connect, d);
    }
    function send(obj) {
        if (ws && ws.readyState === 1) ws.send(JSON.stringify(obj));
    }
    function onLobbyMessage(m) {
        if (m.t === "status") {
            room = { state: m.state, players: m.players || [], settings: cleanSettings(m.settings) };
            if (seat && room.state === "PLAYING") seat.locked = true;
            if (seat && room.settings) seat.dirty = false;
            renderRoom();
            updateOpponent();
        } else if (m.t === "joined") {
            joining = false;
            seat = { role: m.role, token: m.token, nick: $("nick").value.trim(), peerReady: false, locked: false, dirty: false, settings: cleanSettings(m.settings) || prefs() };
            startGame();
        } else if (m.t === "error") {
            joining = false;
            if (seat && (m.code === "NOT_HOST" || m.code === "SETTINGS_LOCKED")) {
                if (m.code === "SETTINGS_LOCKED") seat.locked = true;
                seat.dirty = false;
                $("ov-msg").textContent = ERRORS[m.code];
                if (room.settings) { seat.settings = room.settings; writeSel("ov-", room.settings); }
                renderSettings();
                return;
            }
            setMsg(ERRORS[m.code] || ("Error: " + m.code));
            renderRoom();
        } else if (m.t === "reset") {
            if (seat) endGame(m.reason === "PEER_LEFT" ? "Opponent left" : "Connection lost");
        }
    }
    function updateOpponent() {
        if (!seat) return;
        var i = seat.role === "host" ? 1 : 0;
        $("opp").textContent = room.players[i] || "...";
    }
    function onJoin() {
        if (seat || joining) return;
        var nick = $("nick").value.trim();
        if (!NICK_RE.test(nick)) { setMsg(ERRORS.BAD_NICK); return; }
        storeSet("bvn.nick", nick);
        setMsg("");
        joining = true;
        renderRoom();
        send({ t: "join", nick: nick, password: $("pass").value, settings: prefs() });
    }
    function loadRuffle() {
        quietRuffle();
        if (window.RufflePlayer) return Promise.resolve();
        if (ruffleLoading) return ruffleLoading;
        ruffleLoading = new Promise(function (resolve, reject) {
            var s = document.createElement("script");
            s.src = RUFFLE_URL;
            s.onload = resolve;
            s.onerror = function () { ruffleLoading = null; reject(new Error("Failed to load Ruffle")); };
            document.head.appendChild(s);
        });
        return ruffleLoading;
    }
    function startGame() {
        $("ping").textContent = "-";
        $("opp").textContent = "...";
        $("invite").value = location.href;
        hideStall();
        hideDesync();
        hideMatch();
        $("overlay").classList.toggle("hidden", seat.role !== "host");
        $("ov-msg").textContent = "";
        writeSel("ov-", seat.settings);
        renderSettings();
        showScreen("game");
        updateOpponent();
        var mine = seat;
        loadRuffle().then(function () {
            if (seat !== mine) return;
            var params = { web: "1", role: mine.role, token: mine.token, nick: mine.nick, relayHost: "bvn-game", relayPort: "17511" };
            if (mine.role === "host") {
                params.inputDelay = String(mine.settings.inputDelay);
                params.hp = String(mine.settings.hp);
                params.time = String(mine.settings.time);
            }
            var ruffle = window.RufflePlayer.newest();
            player = ruffle.createPlayer();
            $("player").appendChild(player);
            player.load({
                url: SWF_URL,
                autoplay: "on",
                letterbox: "on",
                allowScriptAccess: true,
                socketProxy: [{ host: "bvn-game", port: 17511, proxyUrl: RELAY + "/game" }],
                parameters: params
            });
            focusPlayer();
        }).catch(function () {
            if (seat === mine) { send({ t: "leave" }); endGame("Failed to load the game"); }
        });
    }
    function hideMatch() { $("match").textContent = ""; $("match").classList.add("hidden"); $("roomset").classList.add("hidden"); }
    function showMatch(d) {
        var hp = Number(d.hp), t = Number(d.time);
        if (!isFinite(hp) || !isFinite(t)) return;
        $("match").textContent = "Life " + Math.round(hp * 100) + "% · Time " + (t < 0 ? "∞" : t + "s");
        $("match").classList.remove("hidden");
        $("roomset").classList.add("hidden");
    }
    function focusPlayer() {
        if (!player) return;
        try { player.tabIndex = 0; player.focus(); } catch (e) { }
    }
    function destroyPlayer() {
        if (player) {
            try { if (typeof player.bvnLeave === "function") player.bvnLeave(); } catch (e) { }
            try { player.remove(); } catch (e) { }
            player = null;
        }
        $("player").textContent = "";
    }
    function endGame(text) {
        seat = null;
        destroyPlayer();
        hideStall();
        hideDesync();
        hideMatch();
        $("ended-msg").textContent = text;
        showScreen("ended");
    }
    function leave(text) {
        send({ t: "leave" });
        seat = null;
        destroyPlayer();
        hideStall();
        hideDesync();
        hideMatch();
        setMsg(typeof text === "string" ? text : "");
        showScreen("lobby");
        renderRoom();
    }
    function copyInvite() {
        var inp = $("invite");
        var done = function () { $("btn-copy").textContent = "Copied"; setTimeout(function () { $("btn-copy").textContent = "Copy"; }, 1500); };
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(inp.value).then(done, function () { inp.select(); });
        } else {
            inp.select();
            try { document.execCommand("copy"); done(); } catch (e) { }
        }
    }
    window.bvnOnEvent = function (name, json) {
        var data = json;
        if (typeof json === "string") { try { data = JSON.parse(json); } catch (e) { data = {}; } }
        data = data || {};
        if (!seat) return;
        switch (name) {
            case "peerReady":
                seat.peerReady = true;
                $("overlay").classList.add("hidden");
                lockSettings();
                focusPlayer();
                break;
            case "matchStart":
                lockSettings();
                focusPlayer();
                break;
            case "matchSettings":
                lockSettings();
                showMatch(data);
                break;
            case "ping":
                if (typeof data.rtt === "number") $("ping").textContent = Math.round(data.rtt) + " ms";
                break;
            case "matchEnd":
                leave("Match finished");
                break;
            case "stall":
                $("stall").textContent = "Waiting for opponent\u2026 " + (Math.max(0, Number(data.ms) || 0) / 1000).toFixed(1) + "s";
                $("stall").classList.remove("hidden");
                break;
            case "resume":
                hideStall();
                break;
            case "desync":
                console.warn("Desync detected", data);
                $("desync").textContent = "Desync detected (round " + data.round + ")";
                $("desync").classList.remove("hidden");
                clearTimeout(desyncTimer);
                desyncTimer = setTimeout(hideDesync, 5000);
                break;
            case "disconnected":
                endGame(REASONS[data.reason] || "Connection lost");
                break;
            case "error":
                console.warn("SWF error:", data.msg);
                break;
        }
    };
    $("btn-join").addEventListener("click", onJoin);
    $("btn-leave-game").addEventListener("click", function () { leave(); });
    $("btn-leave-wait").addEventListener("click", function () { leave(); });
    $("btn-back").addEventListener("click", function () { showScreen("lobby"); renderRoom(); });
    $("btn-copy").addEventListener("click", copyInvite);
    $("nick").addEventListener("keydown", function (e) { if (e.key === "Enter") onJoin(); });
    $("pass").addEventListener("keydown", function (e) { if (e.key === "Enter") onJoin(); });
    $("player-box").addEventListener("click", focusPlayer);
    $("nick").value = storeGet("bvn.nick") || "";
    ["delay", "hp", "time"].forEach(function (k) {
        $("ov-" + k).innerHTML = $(k).innerHTML;
        $(k).addEventListener("change", function () { if (!$(k).disabled) savePrefs(readSel("")); });
        $("ov-" + k).addEventListener("change", onHostChange);
    });
    renderRoom();
    connect();
})();
