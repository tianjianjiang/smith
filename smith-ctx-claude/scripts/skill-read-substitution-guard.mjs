#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve, basename } from "node:path";
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";

const CONFIG_PATH = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "skill-read-config.json",
);
const DEFAULT_SKILL_ROOT_MARKERS = ["/.claude/skills/", "/.smith/", "/skills/"];

function skillRootMarkers() {
  try {
    const config = JSON.parse(readFileSync(CONFIG_PATH, "utf-8"));
    const markers = config.skillRootMarkers;
    return Array.isArray(markers) && markers.length
      ? markers
      : DEFAULT_SKILL_ROOT_MARKERS;
  } catch {
    return DEFAULT_SKILL_ROOT_MARKERS;
  }
}

function isSkillDefinition(filePath, markers) {
  if (basename(filePath) !== "SKILL.md") return false;
  return markers.some((marker) => filePath.includes(marker));
}

function reminder(filePath) {
  return (
    `skill-read-substitution-guard: you are Reading '${filePath}'. To USE a ` +
    `skill, invoke it via the Skill tool (which loads its SKILL.md and runs ` +
    `it) - Reading the SKILL.md only follows it by hand and drifts. Read it ` +
    `directly ONLY to quote or edit it.`
  );
}

function main() {
  const input = readHookInput();
  if (!input || typeof input !== "object") return;
  if (input.tool_name !== "Read") return;

  const filePath = input.tool_input && input.tool_input.file_path;
  if (typeof filePath !== "string") return;
  if (!isSkillDefinition(filePath, skillRootMarkers())) return;

  const message = reminder(filePath);
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

main();
