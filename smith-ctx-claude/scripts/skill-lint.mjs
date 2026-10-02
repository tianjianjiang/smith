#!/usr/bin/env node
import { existsSync, lstatSync, readdirSync, readFileSync, statSync } from "node:fs";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";
import {
  SERENA_TOOL_PREFIX,
  SERENA_WRITE_TOOLS,
  findSerenaProjectRoot,
} from "../../smith-git/scripts/lib/serena-root.mjs";

const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SKILL_FILE_NAME = "SKILL.md";
const NATIVE_WRITE_TOOLS = new Set(["Edit", "Write"]);
const SERENA_MULTIPLE_FILE_TOOL = "replace_in_files";
const FENCE_OPENING = /^\s*(?:(`{3,})[^`]*|(~{3,}).*)$/;
const INLINE_CODE = /`[^`]*`/g;
const PLACEHOLDER = /«[^»]*»/g;
const QUOTED_VALUE = /^(["'])(.*)\1$/;
const BLOCK_SCALAR_MARKER = /^[>|][+-]?$/;
const INDENTED_LINE = /^\s/;
const NON_TICKET_PREFIXES = "ADR|ISO|UTF|SHA|RFC|GPT";
const WHEN_TO_USE = /\buse (?:when|whenever|before|first|for)\b/i;

const CONTENT_RULES = [
  {
    rule: "date",
    patterns: [/\b(?:19|20)\d{2}-(?:0[1-9]|1[0-2])(?:-(?:0[1-9]|[12]\d|3[01]))?\b/],
  },
  {
    rule: "reference",
    patterns: [
      /\b(?:pull|issues)\/\d+\b/,
      /\bPRs? #?\d+\b/,
      /\b(?:pull request|issue)s? #\d+\b/i,
      /\(#\d+\)/,
      /\[#\d+\]/,
      /\b[\w.-]+\/[\w.-]+#\d+\b/,
      /\bcommit [0-9a-f]{7,40}\b/i,
      new RegExp(`\\b(?!(?:${NON_TICKET_PREFIXES})-)[A-Z]{2,10}-\\d{2,}\\b`),
    ],
  },
  {
    rule: "status",
    patterns: [
      /\bas of\b/i,
      /\bawaiting (?:review|merge|approval)\b/i,
      /\bnot yet (?:merged|shipped|released)\b/i,
    ],
  },
  {
    rule: "history",
    patterns: [
      /\bprior version of this (?:file|skill)\b/i,
      /\bthis (?:file|skill) previously\b/i,
      /\bincident (?:history|walkthrough)\b/i,
      /\bincident this guards against\b/i,
      /^\s*correction:/i,
      /\brecurrence was\b/i,
      /\bwas retired after\b/i,
    ],
  },
];

function frontmatterFinding(text) {
  return { line: 1, rule: "frontmatter", text };
}

function unquoted(value) {
  const quoted = QUOTED_VALUE.exec(value);
  return quoted ? quoted[2] : value;
}

function indentedTextBelow(frontmatter, index) {
  const below = frontmatter.slice(index + 1);
  const end = below.findIndex((line) => line.trim() !== "" && !INDENTED_LINE.test(line));
  return (end === -1 ? below : below.slice(0, end))
    .map((line) => line.trim())
    .filter(Boolean)
    .join(" ");
}

function frontmatterFindings(lines, skillDirectoryName) {
  if (lines[0] !== "---") return [frontmatterFinding("file does not open with ---")];
  const closing = lines.indexOf("---", 1);
  if (closing === -1) return [frontmatterFinding("frontmatter is not closed with ---")];
  const fields = new Map();
  const frontmatter = lines.slice(1, closing);
  frontmatter.forEach((line, index) => {
    const separator = line.indexOf(":");
    if (separator <= 0 || INDENTED_LINE.test(line)) return;
    const value = unquoted(line.slice(separator + 1).trim());
    const textBelow = indentedTextBelow(frontmatter, index);
    const fieldValue = BLOCK_SCALAR_MARKER.test(value)
      ? textBelow
      : [value, textBelow].filter(Boolean).join(" ");
    fields.set(line.slice(0, separator).trim(), fieldValue);
  });
  const findings = [];
  if (fields.get("name") !== skillDirectoryName) {
    findings.push(frontmatterFinding(`name must be ${skillDirectoryName}`));
  }
  const description = fields.get("description");
  if (!description) {
    findings.push(frontmatterFinding("description is missing or empty"));
  } else if (!WHEN_TO_USE.test(description)) {
    findings.push(
      frontmatterFinding('description does not say when to use the skill ("Use when …")'),
    );
  }
  return findings;
}

function fenceOpening(text) {
  const opening = FENCE_OPENING.exec(text);
  return opening ? opening[1] || opening[2] : "";
}

function closesFence(text, opening) {
  const marker = text.trim();
  return marker.length >= opening.length && marker === opening[0].repeat(marker.length);
}

function brokenRule(prose) {
  const broken = CONTENT_RULES.find(({ patterns }) =>
    patterns.some((pattern) => pattern.test(prose)),
  );
  return broken && broken.rule;
}

function contentFindings(lines) {
  const findings = [];
  let openFence = "";
  let openFenceLine = 0;
  lines.forEach((text, index) => {
    if (openFence) {
      if (closesFence(text, openFence)) openFence = "";
      return;
    }
    openFence = fenceOpening(text);
    if (openFence) {
      openFenceLine = index + 1;
      return;
    }
    const rule = brokenRule(text.replace(INLINE_CODE, "").replace(PLACEHOLDER, ""));
    if (rule) findings.push({ line: index + 1, rule, text: text.trim() });
  });
  if (openFence) {
    findings.push({
      line: openFenceLine,
      rule: "fence",
      text: "code fence is never closed, so the lines after it were not checked",
    });
  }
  return findings;
}

function fileFindings(path) {
  let content;
  try {
    content = readFileSync(path, "utf-8");
  } catch (error) {
    return [{ line: 1, rule: "unreadable", text: error.code || "read failed" }];
  }
  const lines = content.split(/\r?\n/);
  const skillDirectoryName = basename(dirname(resolve(path)));
  return [...frontmatterFindings(lines, skillDirectoryName), ...contentFindings(lines)];
}

function lintSkillFile(path) {
  return fileFindings(path).map(
    (finding) => `${path}:${finding.line}: ${finding.rule}: ${finding.text}`,
  );
}

function isDirectory(path) {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function isAbsent(path) {
  try {
    lstatSync(path);
    return false;
  } catch (error) {
    return error.code === "ENOENT" || error.code === "ENOTDIR";
  }
}

function skillFilesUnder(root) {
  if (!isDirectory(root)) return [];
  return ["", ...readdirSync(root).sort()]
    .map((name) => join(root, name, SKILL_FILE_NAME))
    .filter((path) => !isAbsent(path));
}

function serenaWrittenSkillFiles(tool, toolInput, sessionDirectory) {
  if (!SERENA_WRITE_TOOLS.has(tool)) return [];
  const root = findSerenaProjectRoot(process.env.CLAUDE_PROJECT_DIR) || sessionDirectory;
  const target = typeof toolInput.relative_path === "string" ? toolInput.relative_path : "";
  const path = resolve(root, target);
  if (basename(path) === SKILL_FILE_NAME) return existsSync(path) ? [path] : [];
  return tool === SERENA_MULTIPLE_FILE_TOOL ? skillFilesUnder(path) : [];
}

function nativeWrittenSkillFiles(toolInput, sessionDirectory) {
  const target = toolInput.file_path;
  if (typeof target !== "string" || basename(target) !== SKILL_FILE_NAME) return [];
  const path = isAbsolute(target) ? target : resolve(sessionDirectory, target);
  return existsSync(path) ? [path] : [];
}

function writtenSkillFiles(input) {
  const toolName = typeof input.tool_name === "string" ? input.tool_name : "";
  const toolInput = input.tool_input || {};
  const sessionDirectory = input.cwd || process.cwd();
  if (SERENA_TOOL_PREFIX.test(toolName)) {
    const tool = toolName.replace(SERENA_TOOL_PREFIX, "");
    return serenaWrittenSkillFiles(tool, toolInput, sessionDirectory);
  }
  return NATIVE_WRITE_TOOLS.has(toolName)
    ? nativeWrittenSkillFiles(toolInput, sessionDirectory)
    : [];
}

function hookFindings(input) {
  try {
    return writtenSkillFiles(input).flatMap(lintSkillFile);
  } catch (error) {
    return [`the written skill files could not be checked: ${error.code || "unexpected error"}`];
  }
}

function runAsHook() {
  const input = readHookInput();
  if (!input || typeof input !== "object") return;
  const findings = hookFindings(input);
  if (findings.length === 0) return;
  const reason =
    "skill-lint: a skill file opens with valid frontmatter whose description says when to " +
    "use the skill, closes every code fence, and holds no calendar date, work status, " +
    "incident or history account, and no pull-request, issue, commit or ticket reference. " +
    "Keep the rule and the URL or path of its source; move the rest to a document under " +
    "references/.\n" +
    findings.join("\n");
  process.stdout.write(JSON.stringify({ decision: "block", reason }) + "\n");
}

function runAsCommand(commandArguments) {
  const explicitRoot = commandArguments.includes("--root");
  if (explicitRoot && (commandArguments[0] !== "--root" || commandArguments.length !== 2)) {
    process.stderr.write("skill-lint: --root takes one directory and no file\n");
    process.exitCode = 1;
    return;
  }
  const root = explicitRoot ? commandArguments[1] : REPOSITORY_ROOT;
  const paths = explicitRoot ? [] : commandArguments;
  const files = paths.length > 0 ? paths : skillFilesUnder(root);
  if (files.length === 0) {
    process.stderr.write("skill-lint: found no SKILL.md to check\n");
    process.exitCode = 1;
    return;
  }
  const findings = files.flatMap(lintSkillFile);
  const summary = `skill-lint: checked ${files.length} files, ${findings.length} findings`;
  process.stdout.write([...findings, summary].join("\n") + "\n");
  if (findings.length > 0) process.exitCode = 1;
}

const commandArguments = process.argv.slice(2);
if (commandArguments[0] === "--hook") runAsHook();
else runAsCommand(commandArguments);
