// Minimal static dev server for fourier_sketch: serves index.html and the
// compiled Gleam JS from ./build. No dependencies: `node scripts/dev-server.mjs`
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize } from "node:path";

const root = process.cwd();
const types = {
  ".html": "text/html",
  ".mjs": "text/javascript",
  ".js": "text/javascript",
  ".css": "text/css",
};
const port = Number(process.env.PORT ?? 3000);

createServer(async (req, res) => {
  try {
    const url = new URL(req.url ?? "/", "http://localhost");
    let path = normalize(decodeURIComponent(url.pathname)).replace(/^\/+/, "");
    if (path === "") path = "index.html";
    const file = join(root, path);
    if (!file.startsWith(root)) {
      res.writeHead(403);
      res.end();
      return;
    }
    const body = await readFile(file);
    res.writeHead(200, {
      "content-type": types[extname(file)] ?? "application/octet-stream",
    });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end("not found");
  }
}).listen(port, () => {
  console.log(`fourier_sketch dev server: http://localhost:${port}`);
});