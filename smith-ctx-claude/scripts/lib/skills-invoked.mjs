import { readFileSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { readTranscriptEvents } from "../../../smith-git/scripts/lib/transcript-turns.mjs";

const SKILL_BODY_OPENING = "Base directory for this skill: ";
export const READING_IS_NOT_LOADING =
  "Reading a SKILL.md or recalling it does not load the skill.";
const GATE_TABLE_PATH = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "skill-gate.json");

export function readGateTable() {
  try {
    const table = JSON.parse(readFileSync(GATE_TABLE_PATH, "utf-8"));
    return {
      alwaysLoaded: Array.isArray(table.alwaysLoaded) ? table.alwaysLoaded : [],
      rules: Array.isArray(table.rules) ? table.rules : [],
    };
  } catch {
    return null;
  }
}

function rememberSkillCalls(content, pendingCalls) {
  for (const block of content) {
    const isSkillCall = block && block.type === "tool_use" && block.name === "Skill";
    const skill = isSkillCall && block.input && block.input.skill;
    if (typeof skill === "string" && typeof block.id === "string") pendingCalls.set(block.id, skill);
  }
}

function skillCallsThatSucceeded(content, pendingCalls) {
  return content
    .filter((block) => block && block.type === "tool_result" && block.is_error !== true)
    .map((block) => pendingCalls.get(block.tool_use_id))
    .filter((skill) => typeof skill === "string");
}

function deliveredSkillBodies(content) {
  return content
    .filter((block) => block && block.type === "text" && typeof block.text === "string")
    .filter((block) => block.text.startsWith(SKILL_BODY_OPENING))
    .map((block) => basename(block.text.slice(SKILL_BODY_OPENING.length).split("\n")[0].trim()));
}

function skillsLoadedByEvent(event, pendingCalls) {
  const content = event.message && event.message.content;
  if (!Array.isArray(content)) return [];
  if (event.type === "assistant") {
    rememberSkillCalls(content, pendingCalls);
    return [];
  }
  if (event.type !== "user") return [];
  if (event.isMeta === true) return deliveredSkillBodies(content);
  return skillCallsThatSucceeded(content, pendingCalls);
}

export async function skillsAvailableInSession(transcriptPath) {
  const available = await skillsLoadedInSession(transcriptPath);
  const table = readGateTable();
  for (const skill of table ? table.alwaysLoaded : []) {
    if (typeof skill === "string") available.add(skill.toLowerCase());
  }
  return available;
}

export async function skillsLoadedInSession(transcriptPath) {
  const loaded = new Set();
  const pendingCalls = new Map();
  for await (const event of readTranscriptEvents(transcriptPath)) {
    if (!event || event.isSidechain === true) continue;
    for (const name of skillsLoadedByEvent(event, pendingCalls)) {
      if (name) loaded.add(name.toLowerCase());
    }
  }
  return loaded;
}
