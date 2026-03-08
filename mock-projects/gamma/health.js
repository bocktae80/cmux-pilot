const { execFileSync } = require('child_process');
const path = require('path');

function checkDisk(diskPath) {
  const resolved = path.resolve(diskPath);

  try {
    const output = execFileSync('df', ['-k', resolved], { encoding: 'utf8' });
    const lines = output.trim().split('\n');
    const parts = lines[1].split(/\s+/);

    const totalKb = parseInt(parts[1], 10);
    const usedKb = parseInt(parts[2], 10);
    const availKb = parseInt(parts[3], 10);

    const usedPct = Math.round((usedKb / totalKb) * 100);
    const freeGb = parseFloat((availKb / (1024 * 1024)).toFixed(2));
    const ok = usedPct < 90;

    return {
      status: ok ? 'healthy' : 'critical',
      usedPct,
      freeGb,
      ok,
    };
  } catch (err) {
    return {
      status: 'error',
      usedPct: -1,
      freeGb: -1,
      ok: false,
    };
  }
}

module.exports = { checkDisk };
