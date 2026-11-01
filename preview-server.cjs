const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
// Always read the current file; never serve a cached build or a different folder.
const file = path.join(__dirname, "index.html");
http
  .createServer((req, res) => {
    const pathname = new URL(req.url, "http://127.0.0.1").pathname;
    if (!["/", "/index.html"].includes(pathname)) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }
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
  })
  .listen(4178, "127.0.0.1", () => console.log("Market V3: http://127.0.0.1:4178/"));
