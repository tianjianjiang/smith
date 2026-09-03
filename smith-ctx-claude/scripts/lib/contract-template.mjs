import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));

export const CONTRACT_SOURCE = resolve(
  HERE,
  "..",
  "..",
  "..",
  "smith-subagents",
  "SKILL.md",
);
export const CONTRACT_HEADING = "## Contract template";

export const REQUIRED_CONTRACT =
  "READ-ONLY investigation. Return FINDINGS ONLY — do NOT edit, write, commit, " +
  "push, or call any mutating / external-write tool. Report `file:line` facts and " +
  "quoted evidence, not fixes or actions taken. If a step seems to need a " +
  "mutation, describe it for the main thread instead of doing it. Restate the " +
  "exact values you observed; do not summarize them away.";

export function stripQuoteMarkers(text) {
  return text.replace(/^[ \t]*>[ \t]?/gm, "");
}

export function normalize(text) {
  return text.replace(/\s+/g, " ").trim().toLowerCase();
}

function blockquoteRuns(sectionLines) {
  const runs = [];
  let current = null;
  for (const line of sectionLines) {
    if (line.startsWith(">")) {
      if (!current) {
        current = [];
        runs.push(current);
      }
      current.push(line.replace(/^>[ \t]?/, ""));
      continue;
    }
    current = null;
  }
  return runs;
}

export function canonicalContract(sourcePath) {
  const source = readFileSync(sourcePath || CONTRACT_SOURCE, "utf-8");
  const headingAt = source.indexOf(CONTRACT_HEADING);
  if (headingAt === -1) return null;

  const sectionLines = [];
  for (const line of source.slice(headingAt).split("\n").slice(1)) {
    if (line.startsWith("## ")) break;
    sectionLines.push(line);
  }

  const runs = blockquoteRuns(sectionLines);
  if (runs.length !== 1) return null;

  const quoted = runs[0];
  if (!quoted.length) return null;

  const display = quoted.join("\n");
  const displayNormalized = normalize(stripQuoteMarkers(display));
  const requiredNormalized = normalize(REQUIRED_CONTRACT);

  if (displayNormalized !== requiredNormalized) return null;

  return {
    display,
    required: requiredNormalized,
  };
}
