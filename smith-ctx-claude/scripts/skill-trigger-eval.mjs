#!/usr/bin/env node
import { execFileSync, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPOSITORY_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const PROMPT_DIRECTORY = join(REPOSITORY_ROOT, "smith-ctx-claude", "evals", "skill-trigger");
const SKILL_FILE_NAME = "SKILL.md";
const SKILL_FILE_AT_TOP_LEVEL = /^([^/]+)\/SKILL\.md$/;
const SKILL_TOOL = "Skill";
const WORKING_TREE = "worktree";
const STUB_BODY = "The rules of this skill are now loaded. Continue with the task.";
const DEFAULT_MODEL = "sonnet";
const DEFAULT_CONCURRENCY = 6;
const DEFAULT_TIMEOUT_SECONDS = 120;
const FAILURES_IN_A_ROW_LIMIT = 25;
const LISTING_CHARACTER_BUDGET = "60000";
const HASH_LENGTH = 12;
const DETAIL_LENGTH = 300;
const COMPLETED = "ok";
const USAGE_EXIT_CODE = 2;
const RUN_OPTIONS = ["--source", "--out", "--model", "--concurrency", "--timeout", "--only", "--runs"];
const COMPARE_OPTIONS = ["--only"];
const USAGE = [
  "usage:",
  "  skill-trigger-eval.mjs run --source <git ref | worktree> --out <file.jsonl>",
  "      [--model <name>] [--concurrency <n>] [--timeout <seconds>] [--only <skill,skill>]",
  "      [--runs <n>]",
  "  skill-trigger-eval.mjs compare <before.jsonl> <after.jsonl> [--only <skill,skill>]",
  "",
  "A prompt counts as a trigger when the session calls the Skill tool for the named",
  "skill before the end of the first assistant message that calls any other tool.",
].join("\n");

class UsageError extends Error {}

function git(...gitArguments) {
  return execFileSync("git", ["-C", REPOSITORY_ROOT, ...gitArguments], { encoding: "utf-8" });
}

function resolvedSource(source) {
  if (source === WORKING_TREE) return WORKING_TREE;
  try {
    return git("rev-parse", "--verify", "--quiet", `${source}^{commit}`).trim();
  } catch {
    throw new UsageError(`${source} is neither "${WORKING_TREE}" nor a git commit`);
  }
}

function skillNamesAt(source) {
  if (source === WORKING_TREE) {
    return readdirSync(REPOSITORY_ROOT)
      .filter((name) => existsSync(join(REPOSITORY_ROOT, name, SKILL_FILE_NAME)))
      .sort();
  }
  return git("ls-tree", "-r", "--name-only", source)
    .split("\n")
    .map((path) => SKILL_FILE_AT_TOP_LEVEL.exec(path))
    .filter(Boolean)
    .map((match) => match[1])
    .sort();
}

function skillFileAt(source, skill) {
  if (source === WORKING_TREE) {
    return readFileSync(join(REPOSITORY_ROOT, skill, SKILL_FILE_NAME), "utf-8");
  }
  return git("show", `${source}:${skill}/${SKILL_FILE_NAME}`);
}

function frontmatterOf(content, skill) {
  const lines = content.split(/\r?\n/);
  const closing = lines.indexOf("---", 1);
  if (lines[0] !== "---" || closing === -1) {
    throw new UsageError(`${skill}/${SKILL_FILE_NAME} has no frontmatter`);
  }
  return lines.slice(0, closing + 1).join("\n");
}

function frontmattersAt(source, skills) {
  return new Map(skills.map((skill) => [skill, frontmatterOf(skillFileAt(source, skill), skill)]));
}

function buildProject(project, frontmatters) {
  for (const [skill, frontmatter] of frontmatters) {
    const directory = join(project, ".claude", "skills", skill);
    mkdirSync(directory, { recursive: true });
    writeFileSync(join(directory, SKILL_FILE_NAME), `${frontmatter}\n\n# ${skill}\n\n${STUB_BODY}\n`);
  }
}

function shortHash(text) {
  return createHash("sha256").update(text).digest("hex").slice(0, HASH_LENGTH);
}

function recordedSource(source, frontmatters) {
  if (source !== WORKING_TREE) return source;
  return `${WORKING_TREE}@${shortHash([...frontmatters.values()].join("\n"))}`;
}

function promptCases() {
  return readdirSync(PROMPT_DIRECTORY)
    .filter((name) => name.endsWith(".json"))
    .sort()
    .map((name) => JSON.parse(readFileSync(join(PROMPT_DIRECTORY, name), "utf-8")))
    .flatMap((set) =>
      [
        ["trigger", true, set.should_trigger],
        ["near-miss", false, set.should_not_trigger],
      ].flatMap(([kind, expected, prompts]) =>
        prompts.map((prompt, index) => ({
          key: `${set.skill}/${kind}/${index}`,
          skill: set.skill,
          expected,
          prompt,
          promptHash: shortHash(prompt),
        })),
      ),
    );
}

function readRecords(path) {
  return readFileSync(path, "utf-8")
    .split("\n")
    .map((line, index) => ({ line, number: index + 1 }))
    .filter(({ line }) => line.trim())
    .map(({ line, number }) => {
      try {
        return JSON.parse(line);
      } catch {
        throw new UsageError(`${path}:${number} is not valid JSON`);
      }
    });
}

function completedRunsByKey(records) {
  const byKey = new Map();
  for (const record of records.filter((candidate) => candidate.status === COMPLETED)) {
    const runs = byKey.get(record.key) || new Map();
    runs.set(record.run || 0, record);
    byKey.set(record.key, runs);
  }
  return byKey;
}

function completedRunsOf(byKey, item) {
  return [...(byKey.get(item.key)?.entries() || [])].filter(
    ([, record]) => record.prompt === item.promptHash,
  );
}

function recordsOfThisRun(path, source, model) {
  if (!existsSync(path)) return [];
  const records = readRecords(path);
  const foreign = records.find((record) => record.source !== source || record.model !== model);
  if (foreign) {
    throw new UsageError(
      `${path} holds records of source ${foreign.source} and model ${foreign.model}; ` +
        `this run is source ${source} and model ${model}`,
    );
  }
  return records;
}

function originOf(path, records) {
  const origins = new Set(records.map((record) => `source ${record.source}, model ${record.model}`));
  if (origins.size > 1) {
    throw new UsageError(`${path} mixes records of ${[...origins].join(" and of ")}`);
  }
  return { model: records[0]?.model, label: [...origins][0] || "no record" };
}

function repeatsBySkill(records) {
  const repeats = new Map();
  for (const record of records) {
    repeats.set(record.skill, Math.max(repeats.get(record.skill) || 0, (record.run || 0) + 1));
  }
  return repeats;
}

function parsedEvent(line) {
  try {
    const event = JSON.parse(line);
    return event && typeof event === "object" ? event : null;
  } catch {
    return null;
  }
}

function skillFromInput(json) {
  const input = parsedEvent(json);
  return input && typeof input.skill === "string" ? input.skill : "";
}

function tail(text) {
  return text.trim().slice(-DETAIL_LENGTH);
}

function runPrompt(project, item, model, timeoutSeconds) {
  return new Promise((resolveRun) => {
    const environment = { ...process.env, SLASH_COMMAND_TOOL_CHAR_BUDGET: LISTING_CHARACTER_BUDGET };
    delete environment.CLAUDECODE;
    const child = spawn(
      "claude",
      [
        "-p",
        item.prompt,
        "--output-format",
        "stream-json",
        "--verbose",
        "--include-partial-messages",
        "--setting-sources",
        "project",
        "--strict-mcp-config",
        "--no-session-persistence",
        "--model",
        model,
      ],
      { cwd: project, env: environment, stdio: ["ignore", "pipe", "pipe"] },
    );
    const loaded = [];
    let sawInit = false;
    let sawModelTurn = false;
    let otherToolCalled = false;
    let unparsableLines = 0;
    let pendingSkillInput = null;
    let buffer = "";
    let errorOutput = "";
    let finished = false;
    const finish = (status, detail = "") => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      child.kill("SIGKILL");
      const garbled = status === COMPLETED && unparsableLines > 0;
      resolveRun({
        status: garbled ? "unparsable-output" : status,
        loaded: [...new Set(loaded)],
        detail: garbled ? `${unparsableLines} output lines were not JSON` : detail,
      });
    };
    const timer = setTimeout(() => finish("timeout"), timeoutSeconds * 1000);
    const onStreamEvent = (streamed) => {
      if (streamed.type === "message_start") sawModelTurn = true;
      if (streamed.type === "content_block_start" && streamed.content_block?.type === "tool_use") {
        if (streamed.content_block.name === SKILL_TOOL) pendingSkillInput = "";
        else otherToolCalled = true;
      } else if (streamed.type === "content_block_delta" && pendingSkillInput !== null) {
        if (streamed.delta?.type === "input_json_delta") {
          pendingSkillInput += streamed.delta.partial_json || "";
        }
      } else if (streamed.type === "content_block_stop" && pendingSkillInput !== null) {
        const skill = skillFromInput(pendingSkillInput);
        pendingSkillInput = null;
        if (skill) loaded.push(skill);
        else finish("error", "a Skill call carried no readable skill name");
      } else if (streamed.type === "message_stop" && otherToolCalled) {
        finish(COMPLETED);
      }
    };
    const onEvent = (event) => {
      if (event.type === "system" && event.subtype === "init") {
        sawInit = true;
        if (!Array.isArray(event.skills) || !event.skills.includes(item.skill)) {
          finish("skill-not-listed", "the session did not list the skill under test");
        }
      } else if (event.type === "stream_event") {
        onStreamEvent(event.event || {});
      } else if (event.type === "result") {
        const answered = event.subtype === "success" && event.is_error !== true && sawModelTurn;
        const reported = event.is_error === true ? "an error" : "no error";
        const turn = sawModelTurn ? "after a model turn" : "without a model turn";
        finish(answered ? COMPLETED : "error", `result ${event.subtype}, ${reported}, ${turn}`);
      }
    };
    const onLine = (line) => {
      if (!line.trim()) return;
      const event = parsedEvent(line);
      if (event) onEvent(event);
      else unparsableLines++;
    };
    child.stdout.on("data", (chunk) => {
      buffer += chunk.toString("utf-8");
      const lines = buffer.split("\n");
      buffer = lines.pop();
      lines.forEach(onLine);
    });
    child.stderr.on("data", (chunk) => {
      errorOutput = tail(errorOutput + chunk.toString("utf-8"));
    });
    child.on("error", (error) => finish("not-started", error.message));
    child.on("close", (code, signal) => {
      onLine(buffer);
      finish(sawInit ? "error" : "not-started", `exit ${code ?? signal}: ${errorOutput}`);
    });
  });
}

function rejectUnknownSkills(only, knownSkills) {
  const unknown = only.filter((skill) => !knownSkills.includes(skill));
  if (unknown.length > 0) throw new UsageError(`--only names no skill: ${unknown.join(", ")}`);
}

function selectedCases(only, skills) {
  rejectUnknownSkills(only, skills);
  const cases = promptCases().filter((item) => only.length === 0 || only.includes(item.skill));
  const unlisted = [...new Set(cases.map((item) => item.skill))].filter(
    (skill) => !skills.includes(skill),
  );
  if (unlisted.length > 0) {
    throw new UsageError(`the source has no ${SKILL_FILE_NAME} for: ${unlisted.join(", ")}`);
  }
  if (cases.length === 0) throw new UsageError("no prompt to run");
  return cases;
}

async function runAll(options) {
  const commit = resolvedSource(options.source);
  const skills = skillNamesAt(commit);
  const cases = selectedCases(options.only, skills);
  const frontmatters = frontmattersAt(commit, skills);
  const source = recordedSource(commit, frontmatters);
  const completed = completedRunsByKey(recordsOfThisRun(options.out, source, options.model));
  const pending = cases.flatMap((item) => {
    const done = new Set(completedRunsOf(completed, item).map(([run]) => run));
    return Array.from({ length: options.runs }, (_, run) => ({ ...item, run })).filter(
      (repeat) => !done.has(repeat.run),
    );
  });
  process.stderr.write(
    `skill-trigger-eval: source ${source}, model ${options.model}, ${skills.length} skills, ` +
      `${pending.length} of ${cases.length * options.runs} prompts to run\n`,
  );
  const project = mkdtempSync(join(tmpdir(), "skill-trigger-eval-"));
  let next = 0;
  let failed = 0;
  let failuresInARow = 0;
  const worker = async () => {
    while (next < pending.length && failuresInARow < FAILURES_IN_A_ROW_LIMIT) {
      const item = pending[next++];
      const outcome = await runPrompt(project, item, options.model, options.timeout);
      if (outcome.status !== COMPLETED) failed++;
      failuresInARow = outcome.status === COMPLETED ? 0 : failuresInARow + 1;
      const record = {
        key: item.key,
        run: item.run,
        skill: item.skill,
        expected: item.expected,
        prompt: item.promptHash,
        source,
        model: options.model,
        status: outcome.status,
        loaded: outcome.loaded,
        triggered: outcome.loaded.includes(item.skill),
        ...(outcome.status === COMPLETED ? {} : { detail: outcome.detail }),
      };
      appendFileSync(options.out, JSON.stringify(record) + "\n");
    }
  };
  try {
    buildProject(project, frontmatters);
    appendFileSync(options.out, "");
    await Promise.all(Array.from({ length: options.concurrency }, worker));
  } finally {
    rmSync(project, { recursive: true, force: true });
  }
  if (failuresInARow >= FAILURES_IN_A_ROW_LIMIT) {
    process.stderr.write(
      `skill-trigger-eval: stopped after ${failuresInARow} prompts in a row did not complete; ` +
        `${pending.length - next} were not tried\n`,
    );
  }
  process.stderr.write(`skill-trigger-eval: ran ${next}, ${failed} did not complete\n`);
  if (failed > 0) process.exitCode = 1;
}

function emptyCounts() {
  return { hits: 0, wanted: 0, falseHits: 0, unwanted: 0 };
}

function completedCount(counts) {
  return counts.wanted + counts.unwanted;
}

function countsBySkill(allRecords, cases) {
  const completed = completedRunsByKey(allRecords);
  const bySkill = new Map();
  for (const item of cases) {
    const records = completedRunsOf(completed, item).map(([, record]) => record);
    const counts = bySkill.get(item.skill) || emptyCounts();
    const triggered = records.filter((record) => record.triggered).length;
    if (item.expected) {
      counts.wanted += records.length;
      counts.hits += triggered;
    } else {
      counts.unwanted += records.length;
      counts.falseHits += triggered;
    }
    bySkill.set(item.skill, counts);
  }
  return bySkill;
}

function verdictOf(before, after) {
  if (after.hits < before.hits) return "fell";
  if (after.falseHits > before.falseHits) return "over-triggers";
  if (after.hits > before.hits) return "rose";
  return "same";
}

function compare(beforePath, afterPath, only) {
  const allCases = promptCases();
  const promptedSkills = [...new Set(allCases.map((item) => item.skill))].sort();
  rejectUnknownSkills(only, promptedSkills);
  const skills = only.length > 0 ? [...only].sort() : promptedSkills;
  const cases = allCases.filter((item) => skills.includes(item.skill));
  const beforeRecords = readRecords(beforePath);
  const afterRecords = readRecords(afterPath);
  const beforeOrigin = originOf(beforePath, beforeRecords);
  const afterOrigin = originOf(afterPath, afterRecords);
  if (beforeOrigin.model !== afterOrigin.model) {
    throw new UsageError("the two files were measured on different models");
  }
  const before = countsBySkill(beforeRecords, cases);
  const after = countsBySkill(afterRecords, cases);
  const repeats = repeatsBySkill([...beforeRecords, ...afterRecords]);
  const total = { before: emptyCounts(), after: emptyCounts() };
  const failing = { fell: 0, "over-triggers": 0, incomplete: 0 };
  const lines = [
    `before: ${beforeOrigin.label}`,
    `after: ${afterOrigin.label}`,
    "skill\ttrigger before\ttrigger after\tnear-miss before\tnear-miss after\tverdict",
  ];
  for (const skill of skills) {
    const b = before.get(skill) || emptyCounts();
    const a = after.get(skill) || emptyCounts();
    const expectedCount =
      cases.filter((item) => item.skill === skill).length * (repeats.get(skill) || 1);
    if (completedCount(b) < expectedCount || completedCount(a) < expectedCount) {
      failing.incomplete++;
      lines.push(
        `${skill}\t-\t-\t-\t-\tincomplete: ${completedCount(b)} and ${completedCount(a)} ` +
          `of ${expectedCount} prompt runs completed`,
      );
      continue;
    }
    const verdict = verdictOf(b, a);
    if (verdict in failing) failing[verdict]++;
    for (const field of Object.keys(total.before)) {
      total.before[field] += b[field];
      total.after[field] += a[field];
    }
    lines.push(
      `${skill}\t${b.hits}/${b.wanted}\t${a.hits}/${a.wanted}\t` +
        `${b.falseHits}/${b.unwanted}\t${a.falseHits}/${a.unwanted}\t${verdict}`,
    );
  }
  lines.push(
    `total\t${total.before.hits}/${total.before.wanted}\t${total.after.hits}/${total.after.wanted}\t` +
      `${total.before.falseHits}/${total.before.unwanted}\t` +
      `${total.after.falseHits}/${total.after.unwanted}\t` +
      `${failing.fell} fell, ${failing["over-triggers"]} over-triggers, ` +
      `${failing.incomplete} incomplete`,
  );
  process.stdout.write(lines.join("\n") + "\n");
  if (Object.values(failing).some((count) => count > 0)) process.exitCode = 1;
}

function optionValue(commandArguments, name) {
  const index = commandArguments.indexOf(name);
  if (index === -1) return "";
  const value = commandArguments[index + 1] || "";
  if (!value || value.startsWith("--")) throw new UsageError(`${name} needs a value`);
  return value;
}

function rejectUnknownOptions(commandArguments, knownOptions) {
  const unknown = commandArguments.filter(
    (argument) => argument.startsWith("--") && !knownOptions.includes(argument),
  );
  if (unknown.length > 0) throw new UsageError(`unknown option: ${unknown.join(", ")}`);
}

function positiveInteger(commandArguments, name, fallback) {
  const value = optionValue(commandArguments, name);
  if (!value) return fallback;
  if (!/^[1-9]\d*$/.test(value)) throw new UsageError(`${name} takes a positive whole number`);
  return Number(value);
}

async function main([mode, ...commandArguments]) {
  const only = optionValue(commandArguments, "--only").split(",").filter(Boolean);
  if (mode === "compare") {
    rejectUnknownOptions(commandArguments, COMPARE_OPTIONS);
    const paths = commandArguments.filter(
      (argument, index) => argument !== "--only" && commandArguments[index - 1] !== "--only",
    );
    if (paths.length !== 2) throw new UsageError("compare takes two files");
    compare(paths[0], paths[1], only);
    return;
  }
  if (mode !== "run") throw new UsageError("unknown or incomplete command");
  rejectUnknownOptions(commandArguments, RUN_OPTIONS);
  const source = optionValue(commandArguments, "--source");
  const out = optionValue(commandArguments, "--out");
  if (!source || !out) throw new UsageError("run needs --source and --out");
  await runAll({
    source,
    out,
    model: optionValue(commandArguments, "--model") || DEFAULT_MODEL,
    concurrency: positiveInteger(commandArguments, "--concurrency", DEFAULT_CONCURRENCY),
    timeout: positiveInteger(commandArguments, "--timeout", DEFAULT_TIMEOUT_SECONDS),
    runs: positiveInteger(commandArguments, "--runs", 1),
    only,
  });
}

try {
  await main(process.argv.slice(2));
} catch (error) {
  if (!(error instanceof UsageError)) throw error;
  process.stderr.write(`skill-trigger-eval: ${error.message}\n${USAGE}\n`);
  process.exitCode = USAGE_EXIT_CODE;
}
