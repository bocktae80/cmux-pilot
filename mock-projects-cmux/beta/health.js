function checkDb(connectionString) {
  return new Promise((resolve) => {
    const start = Date.now();
    const delay = Math.floor(Math.random() * 200) + 50;

    setTimeout(() => {
      const latencyMs = Date.now() - start;
      const ok = latencyMs < 300;

      resolve({
        status: ok ? 'healthy' : 'degraded',
        latencyMs,
        ok,
      });
    }, delay);
  });
}

module.exports = { checkDb };
