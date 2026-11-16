#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const EXIT_OK = 0;
const EXIT_USAGE = 2;
const EXIT_REFUSED = 3;
const USAGE = 'usage: behaviour-eval-summary.mjs OUT';
const MARKER_NAME = 'LEAK-FOUND';
const LEAK_SCAN_NAME = 'leak-scan.txt';
const LEAK_SCAN_SIGNAL = 'files-read: yes';
const ARMS_NAME = 'arms.txt';
const RESULT_NAME = 'result.json';
const CHANGE_ARM = 'with-change';
const BASELINE_ARM = 'baseline';
const ITERATION_FOLDER = /^iteration-(\d+)$/;

class Refusal extends Error {}

function refuse(message) {
  throw new Refusal(message);
}

function printable(text) {
  return String(text).replace(/[\u0000-\u001f\u007f]/g, '?');
}

function compareText(left, right) {
  if (left < right) return -1;
  return left > right ? 1 : 0;
}

function pathExists(target) {
  try {
    fs.lstatSync(target);
    return true;
  } catch (error) {
    if (error.code === 'ENOENT') return false;
    return refuse(`cannot tell whether ${printable(path.basename(target))} exists`);
  }
}

function readTextOrRefuse(file, problem) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch {
    return refuse(problem);
  }
}

function assertLeakScanClean(out) {
  if (pathExists(path.join(out, MARKER_NAME))) refuse(`the run folder carries the ${MARKER_NAME} marker`);
  const report = readTextOrRefuse(path.join(out, LEAK_SCAN_NAME), `${LEAK_SCAN_NAME} is missing or unreadable`);
  if (!report.split(/\r?\n/).includes(LEAK_SCAN_SIGNAL)) refuse(`${LEAK_SCAN_NAME} does not say ${LEAK_SCAN_SIGNAL}`);
}

function parseArmsLine(line) {
  const fields = new Map();
  for (const token of line.trim().split(/\s+/)) {
    const separator = token.indexOf('=');
    if (separator <= 0) refuse(`${ARMS_NAME} holds a line that is not made of key=value fields`);
    fields.set(token.slice(0, separator), token.slice(separator + 1));
  }
  return fields;
}

function armKey(skill, arm) {
  return JSON.stringify([skill, arm]);
}

function readArms(out) {
  const text = readTextOrRefuse(path.join(out, ARMS_NAME), `${ARMS_NAME} is missing or unreadable`);
  const arms = new Map();
  for (const line of text.split(/\r?\n/).filter((candidate) => candidate.trim() !== '')) {
    const fields = parseArmsLine(line);
    const skill = fields.get('skill');
    const arm = fields.get('arm');
    const commit = fields.get('commit');
    if (!skill || !commit || ![CHANGE_ARM, BASELINE_ARM].includes(arm)) refuse(`${ARMS_NAME} holds a line without a usable skill, arm and commit`);
    if (arms.has(armKey(skill, arm))) refuse(`${ARMS_NAME} holds two lines for one skill and arm`);
    arms.set(armKey(skill, arm), { skillCommit: commit, evalCommit: fields.get('eval-commit') || null });
  }
  return arms;
}

function listFolders(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).filter((entry) => entry.isDirectory()).map((entry) => entry.name).sort(compareText);
}

function findResultFiles(directory) {
  const entries = fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => compareText(a.name, b.name));
  return entries.flatMap((entry) => {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) return findResultFiles(entryPath);
    return entry.isFile() && entry.name === RESULT_NAME ? [entryPath] : [];
  });
}

function iterationOf(armFolder, file) {
  const folders = path.relative(armFolder, path.dirname(file)).split(path.sep);
  const numbered = folders.filter((folder) => ITERATION_FOLDER.test(folder));
  if (numbered.length === 0) return refuse(`a ${RESULT_NAME} sits outside any iteration-N folder: ${printable(path.relative(armFolder, file))}`);
  return Number(numbered[numbered.length - 1].match(ITERATION_FOLDER)[1]);
}

function parseResult(file, label) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return refuse(`${label} is not readable JSON`);
  }
}

function verdictOf(status) {
  return status === 'PASS' || status === 'FAIL' ? status : 'ERROR';
}

function verdictOfAssertion(assertion) {
  if (typeof assertion?.passed !== 'boolean') return 'ERROR';
  return assertion.passed ? 'PASS' : 'FAIL';
}

function verdictsOf(caseResult, label) {
  const judges = caseResult.judge_results;
  const assertions = caseResult.grading?.assertion_results;
  if (!Array.isArray(judges) && !Array.isArray(assertions)) return refuse(`${label} holds a case with neither judge_results nor grading assertions`);
  const verdicts = Array.isArray(judges) ? judges.map((judge) => verdictOf(judge?.status)) : assertions.map(verdictOfAssertion);
  return verdicts.length > 0 ? verdicts : ['ERROR'];
}

function recordsFromFile(context, file) {
  const label = printable(path.relative(context.out, file));
  const data = parseResult(file, label);
  const model = data?.observed_configuration?.model;
  if (typeof model !== 'string' || model === '') refuse(`${label} names no observed model`);
  if (!Array.isArray(data.case_results)) refuse(`${label} holds no case_results list`);
  const iteration = iterationOf(context.armFolder, file);
  return data.case_results.map((caseResult) => {
    if (typeof caseResult?.case_id !== 'string' || caseResult.case_id === '') refuse(`${label} holds a case without a case_id`);
    const record = {
      skill: context.skill,
      case: caseResult.case_id,
      arm: context.arm,
      iteration,
      model,
      skill_commit: context.armInfo.skillCommit,
    };
    if (context.armInfo.evalCommit) record.eval_commit = context.armInfo.evalCommit;
    record.verdicts = verdictsOf(caseResult, label);
    return record;
  });
}

function collectRecords(out, arms) {
  const records = [];
  for (const skill of listFolders(out)) {
    for (const arm of listFolders(path.join(out, skill))) {
      const armFolder = path.join(out, skill, arm);
      const files = findResultFiles(armFolder);
      if (files.length === 0) continue;
      const armInfo = arms.get(armKey(skill, arm));
      if (!armInfo) refuse(`results under ${printable(skill)}/${printable(arm)} have no line in ${ARMS_NAME}`);
      for (const file of files) records.push(...recordsFromFile({ out, skill, arm, armFolder, armInfo }, file));
    }
  }
  return records;
}

function assertNoRepeats(records) {
  const seen = new Set();
  for (const record of records) {
    const key = JSON.stringify([record.skill, record.case, record.arm, record.iteration]);
    if (seen.has(key)) refuse(`two results claim the same iteration of ${printable(record.skill)} / ${printable(record.case)}`);
    seen.add(key);
  }
}

function sortRecords(records) {
  return [...records].sort((a, b) => compareText(a.skill, b.skill) || compareText(a.case, b.case) || compareText(a.arm, b.arm) || a.iteration - b.iteration);
}

function caseKey(skill, caseId) {
  return JSON.stringify([skill, caseId]);
}

function withoutBaselineSegment(caseId) {
  return caseId.split('.').filter((segment) => segment !== BASELINE_ARM).join('.');
}

function pairedCaseOf(record, changeCases) {
  if (record.arm !== BASELINE_ARM || changeCases.has(caseKey(record.skill, record.case))) return record.case;
  const candidate = withoutBaselineSegment(record.case);
  return changeCases.has(caseKey(record.skill, candidate)) ? candidate : record.case;
}

function groupByCase(records) {
  const changeCases = new Set(records.filter((record) => record.arm === CHANGE_ARM).map((record) => caseKey(record.skill, record.case)));
  const groups = new Map();
  for (const record of records) {
    const pairedCase = pairedCaseOf(record, changeCases);
    const key = caseKey(record.skill, pairedCase);
    if (!groups.has(key)) groups.set(key, { skill: record.skill, case: pairedCase, baselineCase: null, [CHANGE_ARM]: [], [BASELINE_ARM]: [] });
    const group = groups.get(key);
    if (record.arm === BASELINE_ARM) {
      if (group.baselineCase !== null && group.baselineCase !== record.case) refuse(`two baseline cases pair with ${printable(record.skill)} / ${printable(pairedCase)}`);
      group.baselineCase = record.case;
    }
    group[record.arm].push(record.verdicts);
  }
  return [...groups.values()];
}

function allPass(verdicts) {
  return verdicts.every((verdict) => verdict === 'PASS');
}

function evaluateCase(group) {
  const change = group[CHANGE_ARM];
  const baseline = group[BASELINE_ARM];
  const hasError = [...change, ...baseline].some((verdicts) => verdicts.includes('ERROR'));
  const incomplete = hasError || change.length === 0 || baseline.length === 0;
  return {
    incomplete,
    goal: !incomplete && change.every(allPass) && baseline.some((verdicts) => verdicts.includes('FAIL')),
    regression: !incomplete && change.every(allPass) && baseline.every(allPass),
  };
}

function ruleLine(group) {
  const { goal, regression, incomplete } = evaluateCase(group);
  const rules = `goal-rule: ${goal ? 'met' : 'not met'} regression-rule: ${regression ? 'met' : 'not met'}`;
  return `${printable(group.skill)} / ${printable(group.case)}: ${rules}${incomplete ? ' incomplete' : ''}`;
}

function summarise(out) {
  assertLeakScanClean(out);
  const arms = readArms(out);
  const records = sortRecords(collectRecords(out, arms));
  if (records.length === 0) refuse(`no ${RESULT_NAME} with a case was found`);
  assertNoRepeats(records);
  const groups = groupByCase(records).sort((a, b) => compareText(a.skill, b.skill) || compareText(a.case, b.case));
  return [...records.map((record) => JSON.stringify(record)), ...groups.map(ruleLine)];
}

function run(args) {
  if (args.length !== 1) {
    process.stderr.write(`${USAGE}\n`);
    return EXIT_USAGE;
  }
  try {
    process.stdout.write(`${summarise(args[0]).join('\n')}\n`);
    return EXIT_OK;
  } catch (error) {
    const message = error instanceof Refusal ? error.message : `the summary failed: ${error?.code ?? 'internal error'}`;
    process.stderr.write(`Refused: ${message}\n`);
    return EXIT_REFUSED;
  }
}

process.exitCode = run(process.argv.slice(2));
