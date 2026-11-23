import { readFileSync, writeSync } from "node:fs";
import { execFileSync } from "node:child_process";

function noteOnStandardError(message) {
  try {
    writeSync(2, `${message}\n`);
  } catch {
    return;
  }
}

export function readHookInput() {
  let text = "";
  try {
    text = readFileSync(0, "utf-8");
    return JSON.parse(text);
  } catch (error) {
    noteOnStandardError(`hook input unreadable: ${error.code ?? error.name} after reading ${text.length} characters`);
    return null;
  }
}

export function blockWithError(message) {
  writeSync(2, `${message}\n`);
  process.exit(2);
}

export function git(dir, args, options = {}) {
  const { failOpen = false, env } = options;
  try {
    return execFileSync("git", ["-C", dir, ...args], {
      stdio: ["ignore", "pipe", "ignore"],
      encoding: "utf-8",
      env,
    }).trim();
  } catch (err) {
    if (failOpen) return null;
    throw err;
  }
}
