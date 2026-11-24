import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const ai = args.indexOf("--assets");
const assetsDir = ai >= 0 && args[ai + 1] ? path.resolve(args[ai + 1]) : null;
const port = Number(process.env.PORT) || 5173;
const MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".wasm": "application/wasm",
    ".swf": "application/x-shockwave-flash",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".gif": "image/gif",
    ".svg": "image/svg+xml",
    ".xml": "application/xml",
    ".txt": "text/plain; charset=utf-8",
    ".mp3": "audio/mpeg"
};
function resolveIn(root, rel) {
    const full = path.join(root, rel);
    return full.startsWith(root + path.sep) || full === root ? full : null;
}
function isFile(p) {
    try { return fs.statSync(p).isFile(); } catch { return false; }
}
http.createServer((req, res) => {
    let rel;
    try { rel = decodeURIComponent(new URL(req.url, "http://x").pathname); } catch { res.writeHead(400).end("bad request"); return; }
    if (rel.endsWith("/")) rel += "index.html";
    rel = rel.replace(/^\/+/, "");
    const roots = assetsDir ? [here, assetsDir] : [here];
    for (const root of roots) {
        const f = resolveIn(root, rel);
        if (f && isFile(f)) {
            res.writeHead(200, {
                "Content-Type": MIME[path.extname(f).toLowerCase()] || "application/octet-stream",
                "Cache-Control": "no-cache"
            });
            fs.createReadStream(f).pipe(res);
            return;
        }
    }
    res.writeHead(404, { "Content-Type": "text/plain" }).end("not found");
}).listen(port, () => {
    console.log("BvN web dev server: http://localhost:" + port + (assetsDir ? "  (assets: " + assetsDir + ")" : ""));
});
