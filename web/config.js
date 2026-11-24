(function () {
    var prod = window.BVN_PROD || {};
    var h = location.hostname;
    var isLocal = h === "localhost" || h === "127.0.0.1" || h === "[::1]" || /\.localhost$/.test(h);
    var override = null;
    try { override = new URLSearchParams(location.search).get("relay"); } catch (e) { }
    if (override && !/^wss?:\/\/[^\s/]+$/.test(override)) override = null;
    window.BVN_CONFIG = {
        // priority: ?relay= override > localhost default > config.prod.js value
        RELAY_WS_BASE: override || (isLocal ? "ws://localhost:8080" : (prod.RELAY_WS_BASE || "ws://localhost:8080")),
        SWF_URL: "bvn.swf",
        RUFFLE_URL: prod.RUFFLE_URL || "https://unpkg.com/@ruffle-rs/ruffle@0.7.1/ruffle.js"
    };
})();
