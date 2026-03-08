// mock-gamma build (항상 성공, 빠름)
async function build() {
  const steps = ["compile", "bundle"];
  console.log("mock-gamma: building...\n");

  for (let i = 0; i < steps.length; i++) {
    await new Promise(r => setTimeout(r, 500));
    console.log(`  [${i + 1}/${steps.length}] ${steps[i]} done`);
  }

  console.log("\nbuild complete");
  console.log("EXIT_CODE=0");
}

build();
