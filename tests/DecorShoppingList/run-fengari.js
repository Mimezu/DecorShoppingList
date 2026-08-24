"use strict";

const fs = require("fs");
const path = require("path");

function readOption(name, fallback) {
    const index = process.argv.indexOf(name);
    return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

const workspaceRoot = path.resolve(readOption("--root", process.cwd()));
const smokePath = path.resolve(readOption(
    "--smoke",
    path.join(workspaceRoot, "tests", "DecorShoppingList", "smoke.lua")
));
const fengariSpecifier = readOption("--fengari", "fengari");

let fengariPath = fengariSpecifier;
if (path.isAbsolute(fengariSpecifier) || fengariSpecifier.startsWith(".")) {
    fengariPath = path.resolve(fengariSpecifier);
} else {
    fengariPath = require.resolve(fengariSpecifier, { paths: [workspaceRoot, process.cwd()] });
}

const fengari = require(fengariPath);
const { lua, lauxlib, lualib, to_luastring: toLuaString, to_jsstring: toJSString } = fengari;
if (!lua || !lauxlib || !lualib || !toLuaString || !toJSString) {
    throw new Error(`Module is not a compatible Fengari runtime: ${fengariPath}`);
}
if (!fs.existsSync(smokePath)) {
    throw new Error(`Smoke fixture does not exist: ${smokePath}`);
}

process.chdir(workspaceRoot);
const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
const source = fs.readFileSync(smokePath, "utf8");
let status = lauxlib.luaL_loadbuffer(
    state,
    toLuaString(source),
    null,
    toLuaString(smokePath)
);
if (status !== lua.LUA_OK) {
    throw new Error(toJSString(lua.lua_tostring(state, -1)));
}
status = lua.lua_pcall(state, 0, 0, 0);
if (status !== lua.LUA_OK) {
    throw new Error(toJSString(lua.lua_tostring(state, -1)));
}

console.log(`${path.basename(smokePath)}: Fengari mock harness passed (not Wowless or an in-game runtime).`);
