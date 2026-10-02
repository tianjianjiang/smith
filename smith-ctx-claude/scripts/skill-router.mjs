#!/usr/bin/env node
// skill-router.mjs - UserPromptSubmit hook (deterministic skill-trigger assist)
//
// Why: Claude Code auto-triggers a skill only when the model matches the
// skill's frontmatter `description` and invokes the Skill tool, and smith
// skills under-trigger. This hook pattern-matches the prompt against
// skill-triggers.json and injects an ADVISORY list of candidate skills as
// additionalContext. It is a hint; skill-load-gate.mjs is the enforcement.
//
// Contract: reads the UserPromptSubmit hook JSON on stdin, prints a
// hookSpecificOutput JSON with additionalContext on a match, else nothing.
// It acts only on a prompt the owner typed, and never suggests a skill that
// is already loaded in the session. Always exits 0 — a router must never
// block a prompt.
//
// Self-contained: no hardcoded home paths; the table is resolved relative to
// this script so it works in any operator's checkout (smith-skills rule).
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";
import { skillsAvailableInSession } from "./lib/skills-invoked.mjs";

// Caps the skill lines so the injection stays terse. Notes are NOT capped —
// dropping a deterministic reminder to save a line is the wrong trade.
const MAX_RULES_SHOWN = 5;
const OPENINGS_NOT_TYPED_BY_THE_OWNER = ["<task-notification", "Another Claude session"];

function loadRules() {
  try {
    const here = dirname(fileURLToPath(import.meta.url));
    const tablePath = resolve(here, "..", "skill-triggers.json");
    const data = JSON.parse(readFileSync(tablePath, "utf-8"));
    return Array.isArray(data.rules) ? data.rules : [];
  } catch {
    return [];
  }
}

function typedByTheOwner(prompt) {
  const opening = prompt.trimStart();
  return !OPENINGS_NOT_TYPED_BY_THE_OWNER.some((marker) => opening.startsWith(marker));
}

async function skillsAlreadyAvailable(transcriptPath) {
  if (typeof transcriptPath !== "string") return new Set();
  try {
    return await skillsAvailableInSession(transcriptPath);
  } catch {
    return new Set();
  }
}

function namedInPrompt(skill, prompt) {
  const escaped = skill.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(^|[^\\w-])@?${escaped}([^\\w-]|$)`, "i").test(prompt);
}

function matchRules(rules, prompt, available) {
  const matched = [];
  const notes = new Set();
  const seenSkills = new Set();

  for (const rule of rules) {
    if (!rule || typeof rule.pattern !== "string" || !Array.isArray(rule.skills)) continue;
    const skills = rule.skills.filter((skill) => typeof skill === "string" && skill.trim().length > 0);
    if (skills.length === 0) continue;
    let pattern;
    try {
      pattern = new RegExp(rule.pattern, "i");
    } catch {
      continue;
    }
    if (!pattern.test(prompt)) continue;

    const note = typeof rule.note === "string" ? rule.note.trim() : "";
    if (note) notes.add(note);

    const fresh = skills.filter(
      (skill) => !seenSkills.has(skill) && !available.has(skill.toLowerCase()) && !namedInPrompt(skill, prompt),
    );
    if (fresh.length === 0) continue;
    fresh.forEach((skill) => seenSkills.add(skill));
    matched.push({ why: rule.why || "match", skills: fresh });
  }
  return { matched, notes };
}

async function main() {
  const input = readHookInput();
  if (!input || typeof input !== "object") return;
  const prompt = String(input.prompt || "");
  if (!prompt.trim() || !typedByTheOwner(prompt)) return;

  const rules = loadRules();
  if (rules.length === 0) return;

  const available = await skillsAlreadyAvailable(input.transcript_path);
  const { matched, notes } = matchRules(rules, prompt, available);
  if (matched.length === 0 && notes.size === 0) return;

  const lines = matched
    .slice(0, MAX_RULES_SHOWN)
    .map((match) => `- ${match.why} -> ${match.skills.map((skill) => "@" + skill).join(", ")}`);
  const noteLines = [...notes].map((note) => `- note: ${note}`);

  const hasSkillLines = lines.length > 0;
  const header = hasSkillLines
    ? "Skill router (deterministic hook): your input matches these smith skills —"
    : "Skill router (deterministic hook): reminders for your input —";
  const footer = hasSkillLines
    ? "Load the relevant one with the Skill tool. Candidates, not commands."
    : "Reminders only — the matching skills are already loaded or named in your input.";
  const additionalContext = [header, ...lines, ...noteLines, footer].join("\n");

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext,
      },
    }),
  );
}

main().catch(() => {});
