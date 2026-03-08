const http = require("http");
const https = require("https");

function checkHttp(url) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const client = url.startsWith("https") ? https : http;

    const req = client.get(url, (res) => {
      res.resume();
      res.on("end", () => {
        const latencyMs = Date.now() - start;
        resolve({
          status: res.statusCode,
          latencyMs,
          ok: res.statusCode >= 200 && res.statusCode < 300,
        });
      });
    });

    req.on("error", (err) => {
      reject(err);
    });

    req.end();
  });
}

module.exports = { checkHttp };
