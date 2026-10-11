const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const assert = require("node:assert/strict");
const { createRuntime } = require("./lua-runtime.cjs");
const root = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
(async () => {
  const lua = await createRuntime();
  try {
    for (const file of [
      ...fs.readdirSync(root).filter((file) => file.endsWith(".lua")),
      ...fs
        .readdirSync(path.join(root, "client"))
        .filter((n) => n.endsWith(".lua"))
        .map((n) => "client/" + n),
    ]) {
      await lua.doString(`assert(loadfile(${JSON.stringify("/" + file)}))`);
    }
  } finally {
    lua.global.close();
  }
  const manifest = read("fxmanifest.lua");
  for (const match of manifest.matchAll(/["']([^"']+\.(?:lua|js|css|html|png|json))["']/g)) {
    assert(fs.existsSync(path.join(root, match[1])), "Missing manifest file: " + match[1]);
  }
  const clientScripts = manifest.match(/client_scripts\(\{([\s\S]*?)\}\)/)[1];
  const clientPaths = [...clientScripts.matchAll(/"([^"\n]+)"/g)].map((match) => match[1]);
  assert.equal(
    new Set(clientPaths).size,
    clientPaths.length,
    "Duplicate client script declaration",
  );
  assert(
    clientPaths.indexOf("client/state.lua") < clientPaths.indexOf("client.lua"),
    "Client state must load before bootstrap",
  );
  const html = read("web/index.html");
  assert(
    html.indexOf('src="editor/runtime.js"') < html.indexOf('src="app.js"'),
    "Editor runtime must load before bootstrap",
  );
  for (const match of html.matchAll(/(?:src|href)="([^"#]+\.(?:js|css|png))"/g)) {
    assert(manifest.includes('"web/' + match[1] + '"'), "Unpackaged asset: " + match[1]);
  }
  for (const file of fs
    .readdirSync(path.join(root, "web"), { recursive: true })
    .filter((file) => file.endsWith(".js"))) {
    new vm.Script(read("web/" + file), { filename: file });
  }
  const catalog = JSON.parse(read("animations.json"));
  assert.equal(catalog.length, 100);
  assert.equal(new Set(catalog.map((item) => item.id)).size, catalog.length);
  const browser = { window: {} };
  vm.runInNewContext(read("web/animation-catalog.js"), browser);
  assert.equal(JSON.stringify(browser.window.VantaAnimations), JSON.stringify(catalog));
  vm.runInNewContext(read("web/locales.js"), browser);
  const captions = new Set(
    Object.values(browser.window.VantaLocales.messages).flatMap((item) => [item.en, item.fr]),
  );
  for (const item of catalog) {
    for (const field of ["name", "description", "category", "placement", "caution"]) {
      assert(
        !item[field] || captions.has(item[field]),
        "Untranslated animation caption: " + item[field],
      );
    }
  }
  assert(
    !/DirectorFree|unavailableCalls/.test(
      read("client.lua") + read("server.lua") + read("web/app.js"),
    ),
    "Edition gate remains",
  );
  assert(!/display:\s*none/.test(read("web/free-edition.css")), "Hidden edition controls remain");
  console.log(
    "Lua 5.4 and JS syntax, packaged assets, 100 animations, translations and edition gates passed.",
  );
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
