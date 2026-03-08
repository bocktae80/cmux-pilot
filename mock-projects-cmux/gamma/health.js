const fs = require('fs');

function checkDisk(path) {
  return new Promise((resolve, reject) => {
    fs.statfs(path, (err, stats) => {
      if (err) {
        return reject(err);
      }

      const totalBytes = stats.blocks * stats.bsize;
      const freeBytes = stats.bfree * stats.bsize;
      const usedBytes = totalBytes - freeBytes;
      const usedPct = Math.round((usedBytes / totalBytes) * 100);
      const freeGb = +(freeBytes / (1024 ** 3)).toFixed(2);
      const ok = usedPct < 90;

      resolve({
        status: ok ? 'healthy' : 'critical',
        usedPct,
        freeGb,
        ok,
      });
    });
  });
}

module.exports = { checkDisk };
