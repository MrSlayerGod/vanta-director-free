const fs = require("node:fs");
const path = require("node:path");
const { zipSync, unzipSync, strToU8 } = require("fflate");

const root = path.resolve(__dirname, "..");
const manifest = fs.readFileSync(path.join(root, "fxmanifest.lua"), "utf8");
const version = manifest.match(/^version\("([^"]+)"\)/m)[1];
if (version !== require("../package.json").version)
  throw new Error("Package and manifest versions disagree");
const files = new Set([
  "fxmanifest.lua",
  "README.md",
  "INSTALL.md",
  "CHANGELOG.md",
  "SOURCES.md",
  "CONTRIBUTING.md",
  "LICENSE",
  "animations.json",
]);
// Package declared runtime assets, never the checkout or a server's data directory.
for (const match of manifest.matchAll(/"([^"\n]+\.(?:lua|js|css|html|json|png)|data\/\.keep)"/g))
  files.add(match[1]);
const archive = {};
for (const file of [...files].sort()) {
  if (
    file.includes("..") ||
    path.isAbsolute(file) ||
    (file.startsWith("data/") && file !== "data/.keep")
  )
    throw new Error("Unsafe package path: " + file);
  const data = file === "data/.keep" ? new Uint8Array() : fs.readFileSync(path.join(root, file));
  archive["vanta_director_free/" + file] = [data, { mtime: new Date("2020-01-01T00:00:00Z") }];
}
archive["INSTALL.md"] = [
  strToU8(fs.readFileSync(path.join(root, "INSTALL.md"), "utf8")),
  { mtime: new Date("2020-01-01T00:00:00Z") },
];
const zip = zipSync(archive, { level: 9 });
const decoded = unzipSync(zip);
if (Object.keys(decoded).length !== Object.keys(archive).length)
  throw new Error("Archive entry count mismatch");
for (const [file, [data]] of Object.entries(archive)) {
  if (!Buffer.from(decoded[file]).equals(Buffer.from(data)))
    throw new Error("Archive verification failed: " + file);
}
const output = path.join(root, "dist", `VANTA_Director_Free_${version}_EN_Install.zip`);
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, zip);
console.log(`Verified ${Object.keys(decoded).length} archive entries: ${output}`);
