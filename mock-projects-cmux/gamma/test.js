// mock-gamma test runner (빠르고 안정적)
const tests = [
  { name: "render home", ms: 400 },
  { name: "render about", ms: 300 },
  { name: "render search", ms: 500 },
];

async function run() {
  console.log("mock-gamma: running tests...\n");
  let pass = 0, fail = 0;

  for (const t of tests) {
    await new Promise(r => setTimeout(r, t.ms));
    pass++;
    console.log(`  PASS  ${t.name} (${t.ms}ms)`);
  }

  console.log(`\n${pass} passed, ${fail} failed, ${tests.length} total`);
  console.log(`EXIT_CODE=0`);
}

run();
