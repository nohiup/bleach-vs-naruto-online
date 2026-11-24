import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const RUFFLE_VERSION = "0.7.1";
const RUFFLE_DIR = "ruffle-" + RUFFLE_VERSION;
const WARN_BYTES = 25 * 1024 * 1024;
const EXCLUDE_WEB = new Set(["dev-server.mjs", "README.md"]);
const args = process.argv.slice(2);
function flag(name) { return args.includes(name); }
function opt(name, def) {
    const i = args.indexOf(name);
    return i >= 0 && args[i + 1] ? args[i + 1] : def;
}
if (flag("--help")) {
    console.log("usage: node tools/deploy/build-web.mjs [--game <dir>] [--out <dir>] [--self-host-ruffle] [--allow-insecure]\n" +
        "env: RELAY_WS_BASE=wss://relay.example.com  (written to config.prod.js)");
    process.exit(0);
}
const gameDir = path.resolve(opt("--game", path.join(root, "out", "web")));
const outDir = path.resolve(opt("--out", path.join(root, "dist", "web")));
const selfHost = flag("--self-host-ruffle");
const allowInsecure = flag("--allow-insecure");
function fail(msg) { console.error("ERROR: " + msg); process.exit(1); }
function warn(msg) { console.warn("WARNING: " + msg); }
const relay = (process.env.RELAY_WS_BASE || "").replace(/\/+$/, "");
if (relay) {
    if (!/^wss?:\/\/[^\s/]+$/.test(relay)) fail("RELAY_WS_BASE must be scheme://host[:port] without a path, got: " + relay);
    if (!relay.startsWith("wss://") && !allowInsecure) fail("RELAY_WS_BASE must start with wss:// (use --allow-insecure to override)");
} else {
    warn("RELAY_WS_BASE is not set: the site will fall back to ws://localhost:8080 unless opened with ?relay=");
}
function copyDir(src, dst, skip) {
    fs.mkdirSync(dst, { recursive: true });
    for (const e of fs.readdirSync(src, { withFileTypes: true })) {
        if (skip && skip.has(e.name)) continue;
        const s = path.join(src, e.name), d = path.join(dst, e.name);
        if (e.isDirectory()) copyDir(s, d);
        else fs.copyFileSync(s, d);
    }
}
function listFiles(dir, acc = []) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) listFiles(p, acc);
        else acc.push({ p, size: fs.statSync(p).size });
    }
    return acc;
}
function fetchRuffle(dst) {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "bvn-ruffle-"));
    try {
        const pack = spawnSync("npm pack @ruffle-rs/ruffle@" + RUFFLE_VERSION + " --silent", { cwd: tmp, shell: true, encoding: "utf8" });
        const tgz = fs.readdirSync(tmp).find(f => f.endsWith(".tgz"));
        if (pack.status !== 0 || !tgz) fail("npm pack failed: " + (pack.stderr || pack.stdout || "").trim());
        const x = spawnSync("tar", ["-xzf", tgz], { cwd: tmp, encoding: "utf8" });
        if (x.status !== 0) fail("tar extract failed: " + (x.stderr || "").trim());
        const pkg = path.join(tmp, "package");
        if (!fs.existsSync(path.join(pkg, "ruffle.js"))) fail("ruffle.js not found in the packed Ruffle package");
        fs.mkdirSync(dst, { recursive: true });
        for (const f of fs.readdirSync(pkg)) {
            if (/\.(js|wasm|txt|md)$/i.test(f) || /^LICENSE/i.test(f)) fs.copyFileSync(path.join(pkg, f), path.join(dst, f));
        }
    } finally {
        fs.rmSync(tmp, { recursive: true, force: true });
    }
}
// keep the Vercel project link across rebuilds so `vercel deploy --cwd dist/web` targets the same project
const linkDir = path.join(outDir, ".vercel");
const savedLink = fs.existsSync(linkDir) ? fs.mkdtempSync(path.join(os.tmpdir(), "bvn-vercel-")) : null;
if (savedLink) copyDir(linkDir, savedLink);
fs.rmSync(outDir, { recursive: true, force: true });
copyDir(path.join(root, "web"), outDir, EXCLUDE_WEB);
if (savedLink) {
    copyDir(savedLink, linkDir);
    fs.rmSync(savedLink, { recursive: true, force: true });
}
if (fs.existsSync(gameDir) && fs.statSync(gameDir).isDirectory()) {
    copyDir(gameDir, outDir);
    if (!fs.existsSync(path.join(outDir, "bvn.swf"))) warn(gameDir + " has no bvn.swf; the game will not load");
} else {
    warn("game folder not found: " + gameDir + " -- bvn.swf and game assets are MISSING from the bundle (build the game first)");
}
const prod = {};
if (relay) prod.RELAY_WS_BASE = relay;
if (selfHost) {
    console.log("Fetching @ruffle-rs/ruffle@" + RUFFLE_VERSION + " via npm pack ...");
    fetchRuffle(path.join(outDir, RUFFLE_DIR));
    prod.RUFFLE_URL = RUFFLE_DIR + "/ruffle.js";
}
fs.writeFileSync(path.join(outDir, "config.prod.js"), "window.BVN_PROD = " + JSON.stringify(prod, null, 4) + ";\n");
const files = listFiles(outDir);
const total = files.reduce((n, f) => n + f.size, 0);
const mb = n => (n / 1048576).toFixed(2) + " MB";
console.log("\nBundle: " + outDir);
console.log("Files: " + files.length + ", total " + mb(total));
console.log("Largest files:");
files.sort((a, b) => b.size - a.size).slice(0, 10).forEach(f => console.log("  " + mb(f.size).padStart(10) + "  " + path.relative(outDir, f.p).split(path.sep).join("/")));
const big = files.filter(f => f.size > WARN_BYTES);
big.forEach(f => warn(path.relative(outDir, f.p) + " is " + mb(f.size) + " (> 25 MB Cloudflare Pages per-file limit)"));
console.log("RELAY_WS_BASE: " + (relay || "(unset)") + ", Ruffle: " + (selfHost ? "self-hosted " + RUFFLE_DIR : "unpkg CDN"));
