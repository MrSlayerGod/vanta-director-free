const { createRuntime } = require("./lua-runtime.cjs");
(async () => {
  for (const file of ["payload", "library", "client", "collaboration"]) {
    const lua = await createRuntime();
    try {
      await lua.doFile("/tests/" + file + ".lua");
    } finally {
      lua.global.close();
    }
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
