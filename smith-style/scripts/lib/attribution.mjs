import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ATTRIBUTION_PROGRAM = join(dirname(fileURLToPath(import.meta.url)), "..", "attribution.sh");
const ATTRIBUTION_SCRIPT = "~/.smith/smith-style/scripts/attribution.sh";
const ATTRIBUTION_PREFIX = "Assisted-by: ";
const ATTRIBUTION_LINE = /^\s*assisted\p{Pd}by\s*[:\uFF1A]/iu;
const INVISIBLE_CHARACTERS = /[\u200B-\u200D\u2060\uFEFF]/gu;
const FENCE_OPEN = /^\s*(`{3,}|~{3,})/;
const FENCE_CLOSE = /^\s*(`{3,}|~{3,})\s*$/;
const TOOLS_SUFFIX = "( \\[[^\\]]+\\])*";
const ON_BEHALF_OF = /on behalf of/i;

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function expectedAttribution(...modelSourceArguments) {
  let value = "";
  try {
    value = execFileSync("bash", [ATTRIBUTION_PROGRAM, "value", ...modelSourceArguments], {
      cwd: tmpdir(),
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    value = "";
  }
  if (!value) return { expected: "", allowed: null };
  const expected = `${ATTRIBUTION_PREFIX}${value}`;
  return { expected, allowed: new RegExp(`^${escapeRegExp(expected)}${TOOLS_SUFFIX}$`) };
}

function closedFenceLines(lines) {
  const fenced = new Set();
  let opening = null;
  let inside = [];
  for (const [index, line] of lines.entries()) {
    if (opening === null) {
      const open = FENCE_OPEN.exec(line);
      if (open) {
        opening = open[1];
        inside = [index];
      }
      continue;
    }
    inside.push(index);
    const close = FENCE_CLOSE.exec(line);
    if (close && close[1][0] === opening[0] && close[1].length >= opening.length) {
      for (const fencedIndex of inside) fenced.add(fencedIndex);
      opening = null;
    }
  }
  return fenced;
}

function attributionLines(text) {
  const lines = text.split("\n").map((line) => line.replace(/\r$/, ""));
  const fenced = closedFenceLines(lines);
  return lines.filter((line, index) => !fenced.has(index) && ATTRIBUTION_LINE.test(line.replace(INVISIBLE_CHARACTERS, "")));
}

export function attributionProblems(text, { allowed }) {
  if (!allowed) return ["the session model is unknown"];
  const lines = attributionLines(text);
  const problems = [];
  if (lines.length === 0) problems.push("no Assisted-by line");
  for (const line of lines) {
    if (!allowed.test(line)) problems.push(`invalid line '${line}'`);
  }
  if (ON_BEHALF_OF.test(text)) problems.push("the forbidden phrase 'on behalf of'");
  return problems;
}

function recipeText(subject) {
  if (subject.startsWith("slack_")) {
    return [
      `Run '${ATTRIBUTION_SCRIPT}' in a Bash call first, then end the message field with the line it printed,`,
      "unchanged, and pass only the declared fields (channel_id, message, thread_ts).",
    ];
  }
  if (subject.startsWith("gh pr-review")) {
    return [
      `gh pr-review has no --body-file: run '${ATTRIBUTION_SCRIPT}' in a Bash call first, then end a`,
      "single-quoted --body '...' with the line it printed, unchanged.",
    ];
  }
  return [
    "Write the text to a draft file, append the line in a separate Bash call with",
    `'${ATTRIBUTION_SCRIPT} >> FILE', show the file, then pass it with 'git commit -F FILE'`,
    "or 'gh … --body-file FILE'. Never hand-type the line.",
  ];
}

export function rejectionText(subject, problems, expected) {
  return [
    `${subject} blocked: ${problems.join("; ")}.`,
    expected
      ? `Every Assisted-by line must read '${expected}', optionally followed by ' [tool]'.`
      : `Run '${ATTRIBUTION_SCRIPT}' in a Bash call first; if it prints nothing, no model source knows this session's model yet.`,
    ...recipeText(subject),
  ].join(" ");
}
