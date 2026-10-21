// Local caching maven proxy for machines where DNS flips between
// "no such host" and "works" every few minutes, and dl.google.com's maven
// returns 404 for everything.
//
// Gradle points at:
//   http://127.0.0.1:8642/maven/<group>/<artifact>/...   -> huawei -> aliyun(google) -> aliyun(central)
//   http://127.0.0.1:8642/flutterio/<group/...>          -> storage.flutter-io.cn (io.flutter engine artifacts)
//
// Successful responses are cached to disk; later requests are served from
// disk even when every upstream is down. DNS is hardened: on lookup failure
// the query is retried against public resolvers (AliDNS, DNSPod, Google) and
// the connection is placed directly against the resolved IP with proper SNI.
//
// Run: node tool/maven_proxy.mjs 8642

import http from 'node:http';
import https from 'node:https';
import tls from 'node:tls';
import crypto from 'node:crypto';
import dns from 'node:dns';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const PORT = Number(process.argv[2] || 8642);
const CACHE = path.join(os.tmpdir(), 'copycat-maven-proxy');
fs.mkdirSync(CACHE, { recursive: true });

const PUBLIC_DNS = ['223.5.5.5', '119.29.29.29', '8.8.8.8'];

// path prefix -> ordered upstream transform list
const ROUTES = {
  '/maven/': [
    (p) => ['https://repo.huaweicloud.com', '/repository/maven/' + p],
    (p) => ['https://maven.aliyun.com', '/repository/google/' + p],
    (p) => ['https://maven.aliyun.com', '/repository/central/' + p],
  ],
  '/flutterio/': [
    (p) => ['https://storage.flutter-io.cn', '/download.flutter.io/' + p],
    (p) => ['https://download.flutter-io.cn', '/download.flutter.io/' + p],
  ],
};

const resolver = new dns.Resolver();
resolver.setServers(PUBLIC_DNS);

function resolveIp(host) {
  // Try the OS resolver first; on failure pin via public DNS.
  return dns.promises.lookup(host, { all: false })
    .catch(() => new Promise((res, rej) => {
      resolver.resolve4(host, (err, addrs) =>
        err || !addrs.length ? rej(err || new Error('resolve4 empty')) : res(addrs[0]));
    }))
    .then((r) => (typeof r === 'string' ? r : r.address));
}

function fetchUpstream(url, method) {
  return new Promise((resolveAll) => {
    const u = new URL(url);
    const host = u.hostname;
    resolveIp(host).then((ip) => {
      const req = https.request({
        host: ip,
        hostname: host, // cert check against hostname via servername below
        servername: host,
        port: 443,
        path: u.pathname + (u.search || ''),
        method,
        timeout: 30000,
        headers: { Host: host, 'User-Agent': 'copycat-maven-proxy/1' },
        checkServerIdentity: (_h, cert) => tls.checkServerIdentity(host, cert),
      }, (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolveAll({
          status: res.statusCode,
          headers: {
            'content-type': res.headers['content-type'],
            'content-length': res.headers['content-length'],
            etag: res.headers.etag,
            'last-modified': res.headers['last-modified'],
          },
          body: Buffer.concat(chunks),
        }));
      });
      req.on('timeout', () => req.destroy(new Error('timeout')));
      req.on('error', (e) => resolveAll({ status: 0, headers: {}, body: Buffer.alloc(0), error: String(e) }));
      req.end();
    }, (e) => resolveAll({ status: 0, headers: {}, body: Buffer.alloc(0), error: 'dns ' + String(e) }));
  });
}

async function serveUpstreams(routeList, relPath, method) {
  const passes = 3;
  for (let pass = 0; pass < passes; pass++) {
    for (const transform of routeList) {
      const [origin, upPath] = transform(relPath);
      const url = origin + upPath;
      const key = crypto.createHash('sha1').update(url).digest('hex');
      if (method === 'GET') {
        const cached = path.join(CACHE, key);
        if (fs.existsSync(cached)) {
          const body = fs.readFileSync(cached);
          return { status: 200, headers: { 'content-type': 'application/octet-stream', 'content-length': String(body.length), 'x-cache': 'disk' }, body };
        }
      }
      const r = await fetchUpstream(url, method);
      if (r.status >= 200 && r.status < 300 && r.body.length) {
        if (method === 'GET') {
          try { fs.writeFileSync(path.join(CACHE, key), r.body); } catch { /* cache best-effort */ }
        }
        return { status: r.status, headers: r.headers, body: r.body };
      }
      if (r.status === 404) return { status: 404, headers: { 'content-type': 'text/plain' }, body: Buffer.from('not found (upstream 404): ' + url) };
      // 0/timeout/DNS/transient 5xx -> try next upstream / next pass
    }
    await new Promise((res) => setTimeout(res, 4000));
  }
  return { status: 504, headers: { 'content-type': 'text/plain' }, body: Buffer.from('all upstreams failed for ' + relPath) };
}

http.createServer((req, res) => {
  const rel = req.url.slice(1); // strip leading '/'
  const prefix = '/' + rel.split('/')[0] + '/';
  const routeList = ROUTES[prefix];
  if (!routeList) { res.writeHead(404); res.end('unknown route'); return; }
  const restPath = rel.slice(prefix.length - 1); // keep remainder incl. '/'
  serveUpstreams(routeList, restPath, req.method).then((r) => {
    res.writeHead(r.status, { ...r.headers, 'access-control-allow-origin': '*' });
    res.end(r.body);
  });
}).listen(PORT, '127.0.0.1', () => console.log(`copycat maven proxy on 127.0.0.1:${PORT}, cache: ${CACHE}`));
