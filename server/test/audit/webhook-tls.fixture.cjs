const https = require('node:https');
const fs = require('node:fs');
const { createHmac } = require('node:crypto');
let deliveries = 0;
const server = https.createServer({ key: fs.readFileSync('/certs/key.pem'), cert: fs.readFileSync('/certs/cert.pem') }, (req, res) => {
  if (req.url === '/redirect') {
    res.writeHead(302, { location: 'https://127.0.0.1/private' });
    return res.end();
  }
  if (req.url === '/stats') return res.end(JSON.stringify({ deliveries }));
  const chunks = [];
  req.on('data', (part) => chunks.push(part));
  req.on('end', () => {
    const body = Buffer.concat(chunks).toString();
    const expected = createHmac('sha256', 'synthetic-signing-key').update(body).digest('hex');
    if (body !== '{"event":"synthetic.delivery"}' || req.headers['x-audit-signature'] !== expected) {
      res.writeHead(400); return res.end();
    }
    deliveries++;
    res.writeHead(204); res.end();
  });
});
server.listen(443, '0.0.0.0', () => console.log('Synthetic TLS fixture ready'));
