#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import {
  MINIMUM_IDENTIFIER_LENGTH,
  carriesProtectedString,
  identifiersFromGitListing,
  usableIdentifiers,
} from "./lib/protected-text.mjs";

const CONFIG_FILE_NAME = "personal-data-guard.json";
const GIT_IDENTITY_KEYS = "^user\\.(email|name)$";
const GIT_NO_MATCH_STATUS = 1;
const GIT_READ_TIMEOUT_MILLISECONDS = 2000;

const REFUSAL = [
  "Blocked: this tool call carries a string from the user's protected",
  "personal data. An agent or subagent must not use the user's personal",
  "data: not in a command, URL, header, payload, file, search query, or",
  "subagent prompt. Take a route that needs none. If a service requires",
  "some, skip that service and say so in your report. There is no",
  "override: an action that needs the user's personal data is the user's",
  "to run. Source: smith-ctx-claude/references/HOOKS.md,",
  "personal-data-guard.",
].join(" ");

function block() {
  try {
    writeSync(2, `${REFUSAL}\n`);
  } finally {
    process.exit(2);
  }
}

function advise(message) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: message,
      },
      systemMessage: message,
    }) + "\n",
  );
}

function configPath() {
  return (
    process.env.SMITH_PERSONAL_DATA_GUARD_CONFIG ||
    join(
      process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude"),
      CONFIG_FILE_NAME,
    )
  );
}

function configuredIdentifiers() {
  let listed;
  try {
    listed = JSON.parse(readFileSync(configPath(), "utf-8")).protectedIdentifiers;
  } catch (error) {
    return { entries: [], usable: error.code === "ENOENT" };
  }
  if (!Array.isArray(listed)) return { entries: [], usable: false };
  const entries = listed.filter((entry) => typeof entry === "string");
  return { entries, usable: entries.length === listed.length };
}

function gitIdentifiers(directory) {
  try {
    const listing = execFileSync(
      "git",
      ["config", "--get-regexp", GIT_IDENTITY_KEYS],
      {
        cwd: directory,
        stdio: ["ignore", "pipe", "ignore"],
        encoding: "utf-8",
        timeout: GIT_READ_TIMEOUT_MILLISECONDS,
      },
    );
    return { entries: identifiersFromGitListing(listing), usable: true };
  } catch (error) {
    return { entries: [], usable: error.status === GIT_NO_MATCH_STATUS };
  }
}

function advisories(configured, fromGit, identifiers) {
  const notes = [];
  if (!configured.usable) {
    notes.push(
      `${configPath()} could not be read as JSON holding a ` +
        "protectedIdentifiers array of strings, so NOT everything it lists " +
        "is protected. Only the user can repair it.",
    );
  }
  if (!fromGit.usable) {
    notes.push(
      "git could not be read, so git's user.email and user.name are NOT " +
        "protected on this call.",
    );
  }
  if (identifiers.skipped > 0) {
    notes.push(
      `${identifiers.skipped} protected entries were skipped because they ` +
        `are shorter than ${MINIMUM_IDENTIFIER_LENGTH} characters or are ` +
        "part of the home directory path, which nearly every tool call " +
        "carries; use longer, whole strings.",
    );
  }
  if (identifiers.usable.length === 0) {
    notes.push("no protected string is in force, so nothing is protected.");
  }
  return notes;
}

function hookInput() {
  try {
    return JSON.parse(readFileSync(0, "utf-8"));
  } catch {
    return null;
  }
}

function main() {
  const input = hookInput();
  if (!input || typeof input !== "object" || !("tool_input" in input)) return;

  const sessionDirectory =
    typeof input.cwd === "string" && existsSync(input.cwd)
      ? input.cwd
      : process.cwd();
  const configured = configuredIdentifiers();
  const fromGit = gitIdentifiers(sessionDirectory);
  const identifiers = usableIdentifiers(
    [...fromGit.entries, ...configured.entries],
    homedir(),
  );
  if (carriesProtectedString(input.tool_input, identifiers.usable)) block();

  const notes = advisories(configured, fromGit, identifiers);
  if (notes.length) advise(`personal-data-guard: ${notes.join(" ")}`);
}

try {
  main();
} catch (error) {
  advise(
    "personal-data-guard: the guard itself failed, so this call was NOT " +
      `checked: ${(error && error.message) || error}.`,
  );
}
