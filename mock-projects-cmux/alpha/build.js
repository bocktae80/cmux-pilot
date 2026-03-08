// mock-alpha build
async function build() {
  const steps = ["compile", "bundle", "optimize", "emit"];
  console.log("mock-alpha: building...\n");

  for (let i = 0; i < steps.length; i++) {
    await new Promise(r => setTimeout(r, 700));
    console.log(`  [${i + 1}/${steps.length}] ${steps[i]} done`);
  }

  console.log("\nbuild complete");
  console.log("EXIT_CODE=0");
}

build();
