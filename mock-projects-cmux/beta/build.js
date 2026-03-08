// mock-beta build (가끔 실패)
async function build() {
  const steps = ["typecheck", "compile", "bundle", "minify", "sourcemap"];
  console.log("mock-beta: building...\n");

  for (let i = 0; i < steps.length; i++) {
    await new Promise(r => setTimeout(r, 900));
    if (steps[i] === "minify" && Math.random() > 0.8) {
      console.log(`  [${i + 1}/${steps.length}] ${steps[i]} FAILED: out of memory`);
      console.log("\nbuild failed");
      console.log("EXIT_CODE=1");
      process.exit(1);
    }
    console.log(`  [${i + 1}/${steps.length}] ${steps[i]} done`);
  }

  console.log("\nbuild complete");
  console.log("EXIT_CODE=0");
}

build();
