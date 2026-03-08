// mock-beta test runner (더 많은 테스트, 살짝 느림)
const tests = [
  { name: "api health", ms: 300 },
  { name: "api users list", ms: 900 },
  { name: "api users create", ms: 1100 },
  { name: "api orders list", ms: 800 },
  { name: "api orders create", ms: 1500 },
  { name: "api payments", ms: 2000 },
  { name: "api webhooks", ms: 700 },
];

async function run() {
  console.log("mock-beta: running tests...\n");
  let pass = 0, fail = 0;

  for (const t of tests) {
    await new Promise(r => setTimeout(r, t.ms));
    const ok = Math.random() > 0.15; // 85% pass rate
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
