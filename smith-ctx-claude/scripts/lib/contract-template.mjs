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

export function stripQuoteMarkers(text) {
  return text.replace(/^[ \t]*>[ \t]?/gm, "");
}

export function normalize(text) {
  return text.replace(/\s+/g, " ").trim().toLowerCase();
}

function hasPlaceholder(line) {
  return line.includes("«") || line.includes("»");
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
  if (!quoted.some(hasPlaceholder)) return null;

  const firstPlaceholder = quoted.findIndex(hasPlaceholder);
  const fixed = quoted.slice(0, firstPlaceholder);
  if (!fixed.length) return null;
  if (!quoted.slice(firstPlaceholder).every(hasPlaceholder)) return null;

  return {
    display: quoted.join("\n"),
    fixed,
    required: normalize(fixed.join(" ")),
  };
}
