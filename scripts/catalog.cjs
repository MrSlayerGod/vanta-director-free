const fs = require("node:fs");
const path = require("node:path");
const prettier = require("prettier");

async function buildCatalog() {
  const root = path.resolve(__dirname, "..");
  const catalog = JSON.parse(fs.readFileSync(path.join(root, "animations.json"), "utf8"));
  const config = await prettier.resolveConfig(path.join(root, "animations.json"));
  const source = await prettier.format(
    "// Generated from animations.json by npm run catalog.\nwindow.VantaAnimations = " +
      JSON.stringify(catalog, null, 2) +
      ";\n",
    { ...config, parser: "babel" },
  );
  const target = path.join(root, "web/animation-catalog.js");
  if (process.argv.includes("--check")) {
    if (fs.readFileSync(target, "utf8") !== source) throw new Error("Run npm run catalog");
  } else fs.writeFileSync(target, source);
}
buildCatalog().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
