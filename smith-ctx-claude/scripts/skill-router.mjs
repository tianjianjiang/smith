#!/usr/bin/env node
// skill-router.mjs - UserPromptSubmit hook (deterministic skill-trigger assist)
//
// Why: Claude Code auto-triggers a skill only when the model matches the
// skill's frontmatter `description` and invokes the Skill tool. In practice
// smith skills under-trigger (logs: ~0 smith-* Skill invocations) because the
// CLAUDE.md "Read the file" prose competes with that native path and depends on
// model discipline. This hook removes the discipline dependency: it pattern-
// matches the prompt against skill-triggers.json and injects an ADVISORY list
// of candidate skills as additionalContext, every prompt, deterministically.
//
// Contract: reads the UserPromptSubmit hook JSON on stdin, prints a
// hookSpecificOutput JSON with additionalContext on a match, else nothing.
// Always exits 0 — a router must never block a prompt.
//
// Self-contained: no hardcoded home paths; the table is resolved relative to
// this script so it works in any operator's checkout (smith-skills rule).
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Caps the skill lines so the injection stays terse. Notes are NOT capped —
// dropping a deterministic reminder to save a line is the wrong trade.
const MAX_RULES_SHOWN = 5;

function readStdin() {
  try {
    return readFileSync(0, "utf-8");
  } catch {
    return "";
  }
}

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

function main() {
  const raw = readStdin();
  if (!raw.trim()) return;

  let prompt = "";
  try {
    prompt = String(JSON.parse(raw).prompt || "");
  } catch {
    return;
  }
  if (!prompt.trim()) return;

  const rules = loadRules();
  if (rules.length === 0) return;

  const matched = [];
  const notes = new Set();
  const seenSkills = new Set();

  for (const rule of rules) {
    if (!rule || typeof rule.pattern !== "string" || !Array.isArray(rule.skills))
      continue;
  
  
    const skills = rule.skills.filter(
      (s) => typeof s === "string" && s.trim().length > 0,
    );
    if (skills.length === 0) continue;
    let re;
    try {
      re = new RegExp(rule.pattern, "i");
    } catch {
      continue;
    }
    if (!re.test(prompt)) continue;

  
  
  
    const note = typeof rule.note === "string" ? rule.note.trim() : "";
    if (note) notes.add(note);

  
    const fresh = skills.filter((s) => {
      if (seenSkills.has(s)) return false;
    
    
    
      const escaped = s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      if (new RegExp(`(^|[^\\w-])@?${escaped}([^\\w-]|$)`, "i").test(prompt)) {
        return false;
      }
      return true;
    });
    if (fresh.length === 0) continue;
    fresh.forEach((s) => seenSkills.add(s));
    matched.push({ why: rule.why || "match", skills: fresh });
  }

  if (matched.length === 0 && notes.size === 0) return;



  const lines = matched
    .slice(0, MAX_RULES_SHOWN)
    .map((m) => `- ${m.why} -> ${m.skills.map((s) => "@" + s).join(", ")}`);


  const noteLines = [...notes].map((n) => `- note: ${n}`);


  const hasSkillLines = lines.length > 0;
  const header = hasSkillLines
    ? "Skill router (deterministic hook): your input matches these smith skills —"
    : "Skill router (deterministic hook): reminders for your input —";
  const footer = hasSkillLines
    ? "Invoke the relevant one via the Skill tool (or Read its SKILL.md). Candidates, not commands."
    : "Reminders only — the matching skills were already named in your input.";
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

main();
