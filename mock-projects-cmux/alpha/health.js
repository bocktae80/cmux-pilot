const http = require('http');
const https = require('https');

function checkHttp(url) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const client = url.startsWith('https') ? https : http;

    const req = client.get(url, (res) => {
      res.resume();
      res.on('end', () => {
        const latencyMs = Date.now() - start;
        resolve({
          status: res.statusCode,
          latencyMs,
          ok: res.statusCode >= 200 && res.statusCode < 400,
        });
      });
    });

    req.on('error', (err) => {
      const latencyMs = Date.now() - start;
      reject({
        status: 0,
        latencyMs,
        ok: false,
        error: err.message,
      });
    });

    req.end();
  });
}

module.exports = { checkHttp };
