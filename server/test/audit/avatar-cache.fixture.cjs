// Local cache-migration harness: cacheable legacy media shares an origin with
// the actual built Next.js proxy. No browser interception or fake cache API.
const http = require('node:http');
const fs = require('node:fs');
let fixed = false;
let reads = 0;
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAADUlEQVQImWP4////fwAJ+wP9CNHoHgAAAABJRU5ErkJggg==', 'base64');
const server = http.createServer((req, res) => {
  if (req.url === '/cached-avatar.svg') {
    reads++;
    res.writeHead(200, { 'content-type': fixed ? 'image/png' : 'image/svg+xml', 'cache-control': fixed ? 'no-store' : 'public, max-age=86400' });
    return res.end(fixed ? png : '<svg xmlns="http://www.w3.org/2000/svg"><script>window.OLD_AVATAR_EXECUTED=true</script></svg>');
  }
  if (req.url === '/fixture-state') return res.end(JSON.stringify({ fixed, reads }));
  if (req.url === '/fixture-reset' && req.method === 'POST') { fixed = false; reads = 0; return res.end('ok'); }
  if (req.url === '/fixture-fix' && req.method === 'POST') { fixed = true; return res.end('ok'); }
  if (req.url === '/blank') { res.setHeader('content-type', 'text/html'); return res.end('<title>Synthetic cache fixture</title>'); }
  const upstream = http.request({ hostname: '127.0.0.1', port: 55442, path: req.url, method: req.method, headers: req.headers }, response => {
    res.writeHead(response.statusCode, response.headers); response.pipe(res);
  });
  upstream.on('error', () => { res.writeHead(502); res.end(); });
  req.pipe(upstream);
});
server.listen(55443, '127.0.0.1', () => console.log('Cache fixture ready at http://127.0.0.1:55443'));
const timer = setInterval(() => {
  if (fs.existsSync(process.env.AVATAR_CACHE_FIXTURE_STOP)) { clearInterval(timer); server.close(); }
}, 500);
