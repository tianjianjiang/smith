import { readFileSync, writeSync } from "node:fs";
import { execFileSync } from "node:child_process";

export function readHookInput() {
  try {
    return JSON.parse(readFileSync(0, "utf-8"));
  } catch {
    return null;
  }
}

export function blockWithError(message) {
  writeSync(2, `${message}\n`);
  process.exit(2);
}

export function git(dir, args, options = {}) {
  const { failOpen = false } = options;
  try {
    return execFileSync("git", ["-C", dir, ...args], {
      stdio: ["ignore", "pipe", "ignore"],
      encoding: "utf-8",
    }).trim();
  } catch (err) {
    if (failOpen) return null;
    throw err;
  }
}
