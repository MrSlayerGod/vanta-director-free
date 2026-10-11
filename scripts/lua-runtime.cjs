const fs = require("node:fs");
const path = require("node:path");
const { LuaFactory } = require("wasmoon");
async function createRuntime() {
  const root = path.resolve(__dirname, "..");
  const factory = new LuaFactory();
  const files = fs.readdirSync(root).filter((name) => name.endsWith(".lua"));
  files.push(
    ...fs
      .readdirSync(path.join(root, "tests"))
      .filter((name) => name.endsWith(".lua"))
      .map((name) => "tests/" + name),
  );
  files.push(
    ...fs
      .readdirSync(path.join(root, "client"))
      .filter((n) => n.endsWith(".lua"))
      .map((n) => "client/" + n),
  );
  for (const file of files)
    await factory.mountFile("/" + file, fs.readFileSync(path.join(root, file)));
  return factory.createEngine();
}
module.exports = { createRuntime };
