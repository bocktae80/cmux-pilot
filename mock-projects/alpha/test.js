// mock-alpha test runner
const tests = [
  { name: "auth login", ms: 800 },
  { name: "auth logout", ms: 400 },
  { name: "user profile", ms: 600 },
  { name: "user settings", ms: 500 },
  { name: "data fetch", ms: 1200 },
];

async function run() {
  console.log("mock-alpha: running tests...\n");
  let pass = 0, fail = 0;

  for (const t of tests) {
    await new Promise(r => setTimeout(r, t.ms));
    const ok = Math.random() > 0.1; // 90% pass rate
    if (ok) {
      pass++;
      console.log(`  PASS  ${t.name} (${t.ms}ms)`);
    } else {
      fail++;
      console.log(`  FAIL  ${t.name} (${t.ms}ms)`);
    }
  }

  console.log(`\n${pass} passed, ${fail} failed, ${tests.length} total`);
  console.log(`EXIT_CODE=${fail > 0 ? 1 : 0}`);
  process.exit(fail > 0 ? 1 : 0);
}

run();
