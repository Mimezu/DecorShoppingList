"use strict";

const fs = require("fs");
const path = require("path");

function readOption(name, fallback) {
    const index = process.argv.indexOf(name);
    return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

const workspaceRoot = path.resolve(readOption("--root", process.cwd()));
const addonPath = path.resolve(readOption(
    "--addon",
    path.join(workspaceRoot, "Interface", "AddOns", "DecorShoppingList")
));
const parserSpecifier = readOption("--luaparse", "luaparse");

let parserPath = parserSpecifier;
if (path.isAbsolute(parserSpecifier) || parserSpecifier.startsWith(".")) {
    parserPath = path.resolve(parserSpecifier);
} else {
    parserPath = require.resolve(parserSpecifier, { paths: [workspaceRoot, process.cwd()] });
}
const parser = require(parserPath);
if (!parser || typeof parser.parse !== "function") {
    throw new Error(`Module is not a compatible luaparse parser: ${parserPath}`);
}

const tocPath = path.join(addonPath, "DecorShoppingList.toc");
const entries = fs.readFileSync(tocPath, "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#") && line.toLowerCase().endsWith(".lua"));

for (const entry of entries) {
    const filePath = path.join(addonPath, ...entry.split(/[\\/]/));
    parser.parse(fs.readFileSync(filePath, "utf8"), { luaVersion: "5.1" });
}

console.log(`luaparse accepted ${entries.length} TOC Lua files with the Lua 5.1 grammar.`);
