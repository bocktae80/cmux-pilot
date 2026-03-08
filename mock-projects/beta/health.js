function checkDb(connectionString) {
  const latencyMs = Math.floor(Math.random() * 200) + 10;

  return new Promise((resolve) => {
    setTimeout(() => {
      const ok = Boolean(connectionString && connectionString.length > 0);
      resolve({
        status: ok ? 'connected' : 'disconnected',
        latencyMs,
        ok,
      });
    }, latencyMs);
  });
}

module.exports = { checkDb };
