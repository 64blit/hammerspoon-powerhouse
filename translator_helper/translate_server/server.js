const http = require('http');
const fs = require('fs');
const translate = require('@iamtraction/google-translate');

const START_PORT = parseInt(process.env.PORT || '27892', 10);
const MAX_PORT_ATTEMPTS = parseInt(process.env.MAX_PORT_ATTEMPTS || '20', 10);
const PORT_FILE = process.env.PORT_FILE || '/tmp/hs_translate_port.txt';
const HOST = '127.0.0.1';

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('ok');
    return;
  }

  if (req.method !== 'POST' || !req.url.startsWith('/translate')) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('not found');
    return;
  }

  let raw = '';
  req.on('data', (chunk) => { raw += chunk; });
  req.on('end', async () => {
    let payload;
    try {
      payload = JSON.parse(raw || '{}');
    } catch (e) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'invalid json' }));
      return;
    }
    const from = (payload.from || 'auto').toString();
    const to = (payload.to || 'en').toString();

    if (Array.isArray(payload.texts)) {
      try {
        const results = await Promise.all(payload.texts.map(async (t) => {
          const textStr = (t || '').toString();
          if (!textStr || !textStr.trim()) return { text: textStr, from: 'auto' };
          try {
            const res = await translate(textStr, { from, to });
            return { text: res.text, from: res.from && res.from.language && res.from.language.iso };
          } catch (err) {
            return { text: textStr, from: 'auto', error: err.message };
          }
        }));
        res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ translations: results }));
      } catch (e) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message || String(e) }));
      }
      return;
    }

    const text = (payload.text || '').toString();
    if (!text) {
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ text: '' }));
      return;
    }
    try {
      const result = await translate(text, { from, to });
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({
        text: result.text,
        from: result.from && result.from.language && result.from.language.iso,
      }));
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: e.message || String(e) }));
    }
  });
});

function tryListen(port, attemptsLeft) {
  const onError = (e) => {
    server.removeListener('error', onError);
    if (e && e.code === 'EADDRINUSE' && attemptsLeft > 0) {
      console.error(`port ${port} taken, trying ${port + 1}`);
      tryListen(port + 1, attemptsLeft - 1);
    } else {
      console.error(`failed to bind: ${e && e.message}`);
      process.exit(1);
    }
  };
  server.once('error', onError);
  server.listen(port, HOST, () => {
    server.removeListener('error', onError);
    try { fs.writeFileSync(PORT_FILE, String(port)); } catch (_) {}
    console.log(`translate-server listening on http://${HOST}:${port}`);
  });
}

tryListen(START_PORT, MAX_PORT_ATTEMPTS);

process.on('SIGTERM', () => server.close(() => process.exit(0)));
process.on('SIGINT',  () => server.close(() => process.exit(0)));
