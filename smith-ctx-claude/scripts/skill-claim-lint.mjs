#!/usr/bin/env node
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";
import { READING_IS_NOT_LOADING, skillsAvailableInSession } from "./lib/skills-invoked.mjs";

const SKILLS_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const NAMESPACED_NAME = "[a-z0-9-]+(?::[a-z0-9-]+)?";
const SKILL_NAME = `@${NAMESPACED_NAME}(?![\\w/-])`;
const REASON = "\\s*[(（][^)）\\n]*[)）]";
const CLAIM = new RegExp(
  `\\busing\\s+(${SKILL_NAME}(?:${REASON})?(?:(?:\\s*[,、]\\s*(?:and\\s+)?|\\s+and\\s+)${SKILL_NAME}(?:${REASON})?)*)`,
  "gi",
);
const REASONS = new RegExp(REASON, "g");
const CLAIMED_NAME = new RegExp(`@(${NAMESPACED_NAME})`, "gi");
const NEGATION_BEFORE_A_CLAIM = /(?:\bnot|n't|\bwithout|\bnever|\bno\s+longer)(?:\s+(?!only\b)\w+ly)?\s+$/i;
const SKILL_NAME_ALONE_IN_A_CODE_SPAN = new RegExp(`\`(@${NAMESPACED_NAME})\``, "gi");
const QUOTED_OR_CODE =
  /```[\s\S]*?```|`[^`\n]*`|"[^"\n]*"|“[^”\n]*”|「[^」\n]*」|(?<!\w)'[^'\n]*'(?!\w)|‘[^’\n]*’/g;

function claimedSkills(message) {
  const claimed = new Set();
  if (typeof message !== "string") return claimed;
  const prose = message.replace(SKILL_NAME_ALONE_IN_A_CODE_SPAN, "$1").replace(QUOTED_OR_CODE, " ");
  for (const claim of prose.matchAll(CLAIM)) {
    if (NEGATION_BEFORE_A_CLAIM.test(prose.slice(0, claim.index))) continue;
    for (const name of claim[1].replace(REASONS, "").matchAll(CLAIMED_NAME)) claimed.add(name[1].toLowerCase());
  }
  return claimed;
}

function isSkillOfThisRepository(name) {
  return existsSync(resolve(SKILLS_ROOT, name, "SKILL.md"));
}

function listed(names) {
  return names.map((name) => `@${name}`).join(", ");
}

function refusal(unloaded) {
  const several = unloaded.length > 1;
  return (
    `skill-claim-lint: the last message says "using ${listed(unloaded)}" but ` +
    `${several ? "those skills were" : "that skill was"} not loaded in this session. ` +
    `Load ${several ? "them" : "it"} with the Skill tool and act on what ` +
    `${several ? "they direct" : "it directs"}, or take the claim back. ` +
    READING_IS_NOT_LOADING
  );
}

function advisory(unloaded) {
  return (
    `skill-claim-lint: the last message says "using ${listed(unloaded)}", which no Skill ` +
    `call in this session loaded. If that names a skill, load it with the Skill tool.`
  );
}

async function main() {
  const input = readHookInput();
  if (!input || typeof input !== "object") return;
  if (input.stop_hook_active === true) return;

  const claimed = claimedSkills(input.last_assistant_message);
  if (claimed.size === 0) return;
  if (typeof input.transcript_path !== "string") return;

  const available = await skillsAvailableInSession(input.transcript_path);
  const unloaded = [...claimed].filter((name) => !available.has(name));
  if (unloaded.length === 0) return;

  const known = unloaded.filter(isSkillOfThisRepository);
  const decision =
    known.length > 0
      ? { decision: "block", reason: refusal(known) }
      : { systemMessage: advisory(unloaded) };
  process.stdout.write(JSON.stringify(decision) + "\n");
}

main().catch(() => {});
