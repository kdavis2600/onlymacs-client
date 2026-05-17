import { createReadStream, existsSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("./out", import.meta.url)));
const port = Number.parseInt(process.env.PORT || "3000", 10);
const host = process.env.HOST || "0.0.0.0";

const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".ico", "image/x-icon"],
  [".js", "application/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".pkg", "application/octet-stream"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
  [".txt", "text/plain; charset=utf-8"],
  [".webmanifest", "application/manifest+json"],
  [".woff", "font/woff"],
  [".woff2", "font/woff2"],
]);

function isDocsHost(hostHeader) {
  const hostname = String(hostHeader || "")
    .split(":")[0]
    .toLowerCase();
  return hostname === "docs.onlymacs.ai" || hostname === "www.docs.onlymacs.ai";
}

function mapDocsHostPath(pathname, hostHeader) {
  if (!isDocsHost(hostHeader)) {
    return pathname;
  }

  if (pathname === "/") {
    return "/docs";
  }

  if (pathname.startsWith("/docs") || pathname.startsWith("/_next/") || extname(pathname)) {
    return pathname;
  }

  return `/docs${pathname}`;
}

function mapDocsAliasPath(pathname) {
  if (pathname === "/docs/app") {
    return "/docs/mac-app";
  }
  if (pathname.startsWith("/docs/app/")) {
    return pathname.replace("/docs/app", "/docs/mac-app");
  }
  return pathname;
}

function resolvePath(url, hostHeader) {
  const requestPathname = decodeURIComponent(new URL(url, "http://localhost").pathname);
  const pathname = mapDocsAliasPath(mapDocsHostPath(requestPathname, hostHeader));
  const cleaned = normalize(pathname).replace(/^(\.\.[/\\])+/, "");
  let candidate = join(root, cleaned);

  if (pathname === "/" || pathname.endsWith("/")) {
    candidate = join(root, cleaned, "index.html");
  } else if (!extname(candidate)) {
    const htmlCandidate = `${candidate}.html`;
    if (existsSync(htmlCandidate)) {
      candidate = htmlCandidate;
    }
  }

  if (!candidate.startsWith(root)) {
    return null;
  }
  return candidate;
}

function cacheControl(filePath) {
  if (filePath.includes(`${join(root, "_next", "static")}`)) {
    return "public, max-age=31536000, immutable";
  }
  if (filePath.includes(`${join(root, "downloads")}`)) {
    return "public, max-age=3600";
  }
  return "public, max-age=300";
}

function serveFile(req, res, filePath) {
  const stats = statSync(filePath);
  const type = contentTypes.get(extname(filePath)) || "application/octet-stream";

  res.setHeader("Accept-Ranges", "bytes");
  res.setHeader("Cache-Control", cacheControl(filePath));
  res.setHeader("Content-Type", type);
  res.setHeader("Content-Length", stats.size);

  if (filePath.endsWith(".pkg")) {
    res.setHeader("Content-Disposition", "attachment");
  }

  if (req.method === "HEAD") {
    res.writeHead(200);
    res.end();
    return;
  }

  createReadStream(filePath).pipe(res);
}

createServer((req, res) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Method not allowed");
    return;
  }

  const filePath = resolvePath(req.url || "/", req.headers.host);
  if (!filePath || !existsSync(filePath) || !statSync(filePath).isFile()) {
    const notFound = join(root, "404.html");
    if (existsSync(notFound)) {
      res.writeHead(404, { "Content-Type": "text/html; charset=utf-8" });
      createReadStream(notFound).pipe(res);
      return;
    }
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Not found");
    return;
  }

  serveFile(req, res, filePath);
}).listen(port, host, () => {
  console.log(`onlymacs-web listening on ${host}:${port}`);
});
