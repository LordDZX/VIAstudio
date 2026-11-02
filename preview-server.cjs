const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
// Serve the current game file plus its small local SVG assets, without caching.
const root = __dirname;
const file = path.join(root, "index.html");
const assetsRoot = path.join(root, "assets");
http
  .createServer((req, res) => {
    const pathname = new URL(req.url, "http://127.0.0.1").pathname;
    if (["/", "/index.html"].includes(pathname)) {
      fs.readFile(file, (error, data) => {
        if (error) {
          res.writeHead(500);
          res.end("Preview file unavailable");
          return;
        }
        res.writeHead(200, {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-store, no-cache, must-revalidate",
          "X-Market-Build": "flat-v3",
        });
        res.end(data);
      });
      return;
    }
    if (!pathname.startsWith("/assets/")) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }
    let asset;
    try {
      asset = path.resolve(root, `.${decodeURIComponent(pathname)}`);
    } catch {
      res.writeHead(400);
      res.end("Bad asset path");
      return;
    }
    if (!asset.startsWith(assetsRoot + path.sep)) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }
    fs.readFile(asset, (error, data) => {
      if (error) {
        res.writeHead(error.code === "ENOENT" ? 404 : 500);
        res.end(error.code === "ENOENT" ? "Not found" : "Preview asset unavailable");
        return;
      }
      res.writeHead(200, {
        "Content-Type": asset.endsWith(".svg") ? "image/svg+xml; charset=utf-8" : "application/octet-stream",
        "Cache-Control": "no-store, no-cache, must-revalidate",
      });
      res.end(data);
    });
  })
  .listen(4178, "127.0.0.1", () => console.log("Market V3: http://127.0.0.1:4178/"));
