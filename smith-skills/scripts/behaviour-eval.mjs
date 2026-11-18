#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const SCRIPT_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const EGRESS_SCRIPT = path.join(SCRIPT_DIRECTORY, 'behaviour-eval-egress.sh');
const EGRESS_UP_FAILED_AFTER_CHANGE = 4;
const LEAK_SCAN_SCRIPT = path.join(SCRIPT_DIRECTORY, 'behaviour-eval-leak-scan.mjs');

const EXIT_OK = 0;
const EXIT_REFUSED = 2;
const EXIT_VALIDATION_FAILED = 3;
const EXIT_CONTAINER_PRESENT = 4;
const EXIT_PROBE_FAILED = 5;
const EXIT_EGRESS_UP_FAILED = 6;
const EXIT_RUN_INCOMPLETE = 7;
const EXIT_LEAK_SCAN = 9;
const EXIT_SIGNAL_BASE = 128;

const API_KEY_VARIABLE = 'ANTHROPIC_API_KEY';
const OVERRIDE_VARIABLES = ['ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'CLAUDE_CODE_OAUTH_TOKEN'];
const REQUIRED_COMMANDS = ['git', 'docker', 'rdctl', 'trash'];
const CONTAINER_PREFIX = 'skilled-';
const DEFAULT_SECONDS_PER_ITERATION = '1800';
const DEFAULT_BASELINE = 'origin/main';
const DEFAULT_MODEL = 'claude-haiku-5-5';
const DEFAULT_ITERATIONS = '3';
const SAFE_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const SKILLED_TAG = 'v0.3.0';
const SKILLED_REPOSITORY = 'DeadHead04/skillEd';
const SKILLED_ARCHITECTURES = { arm64: 'arm64', x64: 'amd64' };
const SKILLED_PINNED_SHA256 = {
  'skilled_0.3.0_darwin-arm64.tar.gz': 'af432af790b3ee76ade192209d2783e3df168629f6e82db475b4eaa77b8ba306',
  'skilled_0.3.0_linux-arm64.tar.gz': 'a8dec6a37c812d9e740ff8b113a3c2748934c70b44e39d4f2fa9143e51f783e8',
};
const ARM_TREE_FIXTURE_FILE = 'evals/arm-tree-fixture.txt';
const HANDLED_SIGNALS = ['SIGHUP', 'SIGINT', 'SIGTERM'];
const GRACE_MILLISECONDS = 10000;
const LONGEST_TIMER_MILLISECONDS = 2147483647;
const LONGEST_RUN_SECONDS = Math.floor(LONGEST_TIMER_MILLISECONDS / 1000);
const SKILLED_CONFIGURATION_FILES = ['.env', '.skilled.yaml'];

const USAGE = `usage: behaviour-eval.mjs --out «dir» --source «git ref» [--baseline «git ref»] [--model «id»]
                         [--iterations «n»] [--seconds-per-iteration «n»] [--repo «path»] [--skilled «path»]
                         [--help] «skill»...

  --out «dir»          folder for the results; must not exist or be empty, and must lie outside every git work tree
  --source «git ref»   ref the with-change arm is built from
  --baseline «git ref» ref the baseline arm is built from (default ${DEFAULT_BASELINE})
  --model «id»         model the evals run on (default ${DEFAULT_MODEL})
  --iterations «n»     iterations per eval (default ${DEFAULT_ITERATIONS})
  --seconds-per-iteration «n»
                       seconds an arm may run per iteration before the watchdog stops it
                       (default ${DEFAULT_SECONDS_PER_ITERATION})
  --repo «path»        repository holding the skills (default: the checkout this script lives in)
  --skilled «path»     skillEd executable (default: ${SKILLED_TAG} downloaded with gh; its archive must match the SHA-256
                       pinned in this script and the release's .sha256 file and checksums.txt)
  --help               print this text and exit
  «skill»...           skill folders to evaluate, one or more

When a skill's ${ARM_TREE_FIXTURE_FILE} names a folder under evals/fixtures/, each arm gets that folder filled with the whole tree of
the arm's ref, without the skill's evals folder, so a case can use it as its repository fixture.

skillEd starts with exactly PATH, a fresh HOME, a fresh TMPDIR, DOCKER_HOST and, for real runs, ${API_KEY_VARIABLE}. DOCKER_HOST is the
caller's value; when it is unset or empty, the endpoint of the current docker context is used, and the run refuses if that cannot be read.
The key is read from ${API_KEY_VARIABLE}. The run refuses to start while ${OVERRIDE_VARIABLES.join(', ')} is set.
Exit status: 0 every case of every arm and iteration reached PASS or FAIL (the verdicts are in the results, not in the exit status),
2 refused or bad input, 3 skillEd validation failed, 4 a ${CONTAINER_PREFIX}* container already exists, 5 egress probe failed,
6 egress up failed, 7 a real run left a result missing, empty or holding a case that reached neither PASS nor FAIL,
9 leak scan hit or not run, 129, 130 and 143 interrupted.
`;

class Refusal extends Error {
  constructor(message, exitCode = EXIT_REFUSED) {
    super(message);
    this.exitCode = exitCode;
  }
}

class StepFailure extends Error {
  constructor(message, exitCode) {
    super(message);
    this.exitCode = exitCode;
  }
}

function report(message) {
  process.stdout.write(`behaviour-eval: ${message}\n`);
}

function reportProblem(message) {
  process.stderr.write(`behaviour-eval: ${message}\n`);
}

function text(buffer) {
  return buffer.toString('utf8');
}

function childEnvironment() {
  const environment = { ...process.env };
  delete environment[API_KEY_VARIABLE];
  return environment;
}

function signalGroup(child, signal) {
  try {
    process.kill(-child.pid, signal);
  } catch {
    return;
  }
}

function execute(command, args, { cwd, env = childEnvironment(), input, timeoutMs, outputFile, run } = {}) {
  return new Promise((resolve) => {
    const stdout = [];
    const stderr = [];
    const timers = new Set();
    let settled = false;
    let timedOut = false;
    const child = spawn(command, args, { cwd, env, detached: true, stdio: ['pipe', 'pipe', 'pipe'] });
    const later = (milliseconds, action) => timers.add(setTimeout(action, milliseconds));
    const group = {
      kill: () => signalGroup(child, 'SIGKILL'),
      terminate: () => {
        signalGroup(child, 'SIGTERM');
        later(GRACE_MILLISECONDS, group.kill);
      },
    };
    if (run) run.children.add(group);
    if (timeoutMs) {
      later(timeoutMs, () => {
        timedOut = true;
        group.terminate();
      });
    }
    const finish = (status, signal, error) => {
      if (settled) return;
      settled = true;
      for (const timer of timers) clearTimeout(timer);
      if (run) run.children.delete(group);
      const result = { status, signal, error, timedOut, outputError: null, stdout: Buffer.concat(stdout), stderr: Buffer.concat(stderr) };
      if (outputFile) {
        try {
          fs.writeFileSync(outputFile, Buffer.concat([result.stdout, result.stderr]));
        } catch (failure) {
          result.outputError = failure;
          if (run) recordFailure(run, EXIT_RUN_INCOMPLETE);
          reportProblem(`could not write ${outputFile}: ${failure.message}`);
        }
      }
      resolve(result);
    };
    child.stdout.on('data', (chunk) => stdout.push(chunk));
    child.stderr.on('data', (chunk) => stderr.push(chunk));
    child.stdin.on('error', () => {});
    child.on('error', (error) => finish(null, null, error));
    child.on('exit', (status, signal) => {
      later(GRACE_MILLISECONDS, () => {
        group.kill();
        child.stdout.destroy();
        child.stderr.destroy();
        finish(status, signal, null);
      });
    });
    child.on('close', (status, signal) => finish(status, signal, null));
    child.stdin.end(input);
  });
}

function succeeded(result) {
  return result.status === 0;
}

function statusOf(result) {
  return result.status ?? 1;
}

function isExecutableFile(candidate) {
  try {
    fs.accessSync(candidate, fs.constants.X_OK);
    return fs.statSync(candidate).isFile();
  } catch {
    return false;
  }
}

function findOnPath(command) {
  const directories = (process.env.PATH ?? '').split(path.delimiter).filter(Boolean);
  return directories.map((directory) => path.join(directory, command)).find(isExecutableFile) ?? null;
}

function lstatOrNull(target) {
  try {
    return fs.lstatSync(target);
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}

function parseOptions(argv) {
  try {
    const { values, positionals } = parseArgs({
      args: argv,
      allowPositionals: true,
      options: {
        out: { type: 'string' },
        source: { type: 'string' },
        baseline: { type: 'string', default: DEFAULT_BASELINE },
        model: { type: 'string', default: DEFAULT_MODEL },
        iterations: { type: 'string', default: DEFAULT_ITERATIONS },
        'seconds-per-iteration': { type: 'string', default: DEFAULT_SECONDS_PER_ITERATION },
        repo: { type: 'string' },
        skilled: { type: 'string' },
        help: { type: 'boolean' },
      },
    });
    return { ...values, skills: positionals };
  } catch (error) {
    throw new Refusal(`${error.message}\n${USAGE}`);
  }
}

function requireArguments(options) {
  if (!options.out) throw new Refusal('--out is required');
  if (!options.source) throw new Refusal('--source is required');
  if (options.skills.length === 0) throw new Refusal('at least one skill is required');
  if (!/^[1-9][0-9]*$/.test(options.iterations)) throw new Refusal('--iterations must be a positive whole number');
  if (!/^[1-9][0-9]*$/.test(options['seconds-per-iteration'])) throw new Refusal('--seconds-per-iteration must be a positive whole number');
  if (Number(options.iterations) * Number(options['seconds-per-iteration']) > LONGEST_RUN_SECONDS) {
    throw new Refusal(`--iterations times --seconds-per-iteration must be at most ${LONGEST_RUN_SECONDS} seconds, the longest timer Node.js keeps`);
  }
  for (const skill of options.skills) {
    if (!SAFE_NAME.test(skill)) throw new Refusal(`${skill} is not a plain skill folder name`);
  }
  for (const ref of [options.source, options.baseline]) {
    if (ref.startsWith('-')) throw new Refusal(`${ref} is not a git ref`);
  }
}

function requireKeyAndCleanEndpoint() {
  const apiKey = process.env[API_KEY_VARIABLE];
  if (!apiKey) throw new Refusal(`${API_KEY_VARIABLE} must be set and not empty`);
  const overridden = OVERRIDE_VARIABLES.find((name) => process.env[name]);
  if (overridden) throw new Refusal(`${overridden} must not be set: it redirects or replaces the key`);
  return apiKey;
}

function requireCommands() {
  for (const command of REQUIRED_COMMANDS) {
    if (!findOnPath(command)) throw new Refusal(`${command} was not found on PATH`);
  }
}

async function buildGitEnvironment() {
  const listing = await execute('git', ['rev-parse', '--local-env-vars'], { env: { ...childEnvironment(), LC_ALL: 'C' } });
  if (!succeeded(listing)) throw new Refusal('git could not list its own environment variables');
  const environment = childEnvironment();
  const callerControlled = [...text(listing.stdout).split('\n').filter(Boolean), 'GIT_CEILING_DIRECTORIES', 'GIT_DISCOVERY_ACROSS_FILESYSTEM'];
  for (const name of callerControlled) delete environment[name];
  environment.LC_ALL = 'C';
  return environment;
}

async function resolveRepository(options, gitEnvironment) {
  const requested = options.repo ?? SCRIPT_DIRECTORY;
  const toplevel = await execute('git', ['-C', requested, 'rev-parse', '--show-toplevel'], { env: gitEnvironment });
  if (!succeeded(toplevel)) throw new Refusal(`${requested} is not inside a git repository`);
  return options.repo ? path.resolve(options.repo) : text(toplevel.stdout).trim();
}

async function resolveCommit(repo, ref, gitEnvironment) {
  const result = await execute('git', ['-C', repo, 'rev-parse', '--verify', '--quiet', `${ref}^{commit}`], { env: gitEnvironment });
  const commit = text(result.stdout).trim();
  if (!succeeded(result) || !commit) throw new Refusal(`${ref} does not name a commit in ${repo}`);
  return commit;
}

function requireUsableOut(out) {
  let entry = null;
  try {
    entry = fs.statSync(out);
  } catch (error) {
    if (error.code !== 'ENOENT') throw new Refusal(`cannot inspect ${out}: ${error.code}`);
  }
  if (entry === null) return;
  if (!entry.isDirectory()) throw new Refusal(`${out} exists and is not a folder`);
  if (fs.readdirSync(out).length > 0) throw new Refusal(`${out} exists and is not empty; the runner never empties a folder`);
}

function requireFreeWorkPath(work) {
  if (lstatOrNull(work) !== null) throw new Refusal(`${work} already exists; remove it deliberately before running again`);
}

async function requireOutsideGitWorkTree(target, gitEnvironment) {
  let ancestor = target;
  while (!fs.existsSync(ancestor)) ancestor = path.dirname(ancestor);
  const answer = await execute('git', ['-C', fs.realpathSync(ancestor), 'rev-parse', '--is-inside-work-tree'], { env: gitEnvironment });
  const notARepository = answer.status === 128 && /not a git repository/i.test(text(answer.stderr));
  if (!notARepository) throw new Refusal(`${target} must lie outside every git work tree`);
}

async function listSkilledContainers(run) {
  const result = await execute('docker', ['ps', '-a', '--format', '{{.Names}}'], { run });
  if (!succeeded(result)) throw new Refusal('docker could not list containers');
  return text(result.stdout).split('\n').map((name) => name.trim()).filter((name) => name.startsWith(CONTAINER_PREFIX));
}

async function requireNoSkilledContainer() {
  const existing = await listSkilledContainers();
  if (existing.length > 0) {
    throw new Refusal(`containers named ${CONTAINER_PREFIX}* already exist and the runner never removes them: ${existing.join(' ')}`, EXIT_CONTAINER_PRESENT);
  }
}

async function resolveDockerHost() {
  if (process.env.DOCKER_HOST) return process.env.DOCKER_HOST;
  const lookup = await execute('docker', ['context', 'inspect', '--format', '{{.Endpoints.docker.Host}}']);
  const endpoint = text(lookup.stdout).trim();
  if (!succeeded(lookup) || !endpoint) throw new Refusal('the endpoint of the current docker context could not be read, and DOCKER_HOST is not set');
  return endpoint;
}

async function checkPreconditions(options) {
  requireArguments(options);
  const apiKey = requireKeyAndCleanEndpoint();
  requireCommands();
  const gitEnvironment = await buildGitEnvironment();
  const repo = await resolveRepository(options, gitEnvironment);
  const commits = {
    source: await resolveCommit(repo, options.source, gitEnvironment),
    baseline: await resolveCommit(repo, options.baseline, gitEnvironment),
    head: await resolveCommit(repo, 'HEAD', gitEnvironment),
  };
  if (options.skilled && !isExecutableFile(path.resolve(options.skilled))) throw new Refusal(`${options.skilled} is not an executable file`);
  const out = path.resolve(options.out);
  const work = `${out}.work`;
  requireUsableOut(out);
  requireFreeWorkPath(work);
  await requireOutsideGitWorkTree(out, gitEnvironment);
  await requireOutsideGitWorkTree(work, gitEnvironment);
  await requireNoSkilledContainer();
  const dockerHost = await resolveDockerHost();
  return {
    out,
    work,
    repo,
    commits,
    apiKey,
    gitEnvironment,
    skills: options.skills,
    source: options.source,
    baseline: options.baseline,
    model: options.model,
    iterations: options.iterations,
    secondsPerIteration: options['seconds-per-iteration'],
    skilled: options.skilled ? path.resolve(options.skilled) : null,
    dockerHost,
  };
}

function freshFolder(parent, prefix) {
  return fs.mkdtempSync(path.join(parent, prefix));
}

function skilledEnvironment(settings, { withKey }) {
  const environment = {
    HOME: freshFolder(settings.work, 'home-'),
    TMPDIR: freshFolder(settings.work, 'tmp-'),
    DOCKER_HOST: settings.dockerHost,
  };
  if (process.env.PATH) environment.PATH = process.env.PATH;
  if (withKey) environment[API_KEY_VARIABLE] = settings.apiKey;
  return environment;
}

function skilledAssetName() {
  const architecture = SKILLED_ARCHITECTURES[process.arch];
  if (!architecture || !['darwin', 'linux'].includes(process.platform)) {
    throw new StepFailure(`no skillEd release asset is known for ${process.platform} ${process.arch}`, EXIT_REFUSED);
  }
  return `skilled_${SKILLED_TAG.slice(1)}_${process.platform}-${architecture}`;
}

function sha256Of(file) {
  return createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function readDownloadOrRefuse(file) {
  try {
    return fs.readFileSync(file);
  } catch (error) {
    throw new StepFailure(`the skillEd release download holds no readable ${path.basename(file)}: ${error.code ?? 'unknown error'}`, EXIT_REFUSED);
  }
}

function checksumListed(checksumsText, archiveName) {
  const lines = checksumsText.split('\n');
  const match = lines.map((line) => line.trim().split(/\s+/)).find((fields) => fields.at(-1) === archiveName);
  return match ? match[0] : null;
}

async function downloadSkilled(settings, run) {
  const asset = skilledAssetName();
  const archiveName = `${asset}.tar.gz`;
  const downloads = path.join(settings.work, 'download');
  const distribution = path.join(settings.work, 'dist');
  fs.mkdirSync(downloads);
  fs.mkdirSync(distribution);
  const download = await execute('gh', ['release', 'download', SKILLED_TAG, '--repo', SKILLED_REPOSITORY,
    '--pattern', archiveName, '--pattern', `${archiveName}.sha256`, '--pattern', 'checksums.txt', '--dir', downloads], { run });
  if (!succeeded(download)) throw new StepFailure('gh could not download the skillEd release', EXIT_REFUSED);
  const archive = path.join(downloads, archiveName);
  const actual = createHash('sha256').update(readDownloadOrRefuse(archive)).digest('hex');
  const published = readDownloadOrRefuse(`${archive}.sha256`).toString('utf8').trim().split(/\s+/)[0];
  const listed = checksumListed(readDownloadOrRefuse(path.join(downloads, 'checksums.txt')).toString('utf8'), archiveName);
  const pinned = SKILLED_PINNED_SHA256[archiveName];
  if (!pinned) throw new StepFailure(`no pinned SHA-256 is known for ${archiveName}`, EXIT_REFUSED);
  if (actual !== pinned) throw new StepFailure(`the skillEd archive ${archiveName} does not match the SHA-256 pinned in this script`, EXIT_REFUSED);
  if (actual !== published || actual !== listed) throw new StepFailure('the skillEd archive checksum does not match the published checksums', EXIT_REFUSED);
  const extraction = await execute('tar', ['-xzf', archive, '-C', distribution], { run });
  if (!succeeded(extraction)) throw new StepFailure('the skillEd archive could not be extracted', EXIT_REFUSED);
  const executable = path.join(distribution, asset, 'skilled');
  await execute(executable, ['--version'], { cwd: settings.work, env: skilledEnvironment(settings, { withKey: false }),
    outputFile: path.join(settings.out, 'skilled-version.txt'), run });
  return executable;
}

async function extractTree(settings, ref, pathspecs, destination, run) {
  const archive = await execute('git', ['-C', settings.repo, 'archive', '--format=tar', ref, '--', ...pathspecs], { env: settings.gitEnvironment, run });
  if (!succeeded(archive)) throw new StepFailure(`git could not archive ${[ref, ...pathspecs].join(' ')}`, EXIT_REFUSED);
  const extraction = await execute('tar', ['-xf', '-', '-C', destination], { input: archive.stdout, run });
  if (!succeeded(extraction)) throw new StepFailure(`tar could not extract ${ref}`, EXIT_REFUSED);
}

async function fillArmTreeFixture(settings, skill, commit, skillDirectory, run) {
  const namingFile = path.join(skillDirectory, ARM_TREE_FIXTURE_FILE);
  if (!fs.existsSync(namingFile)) return;
  const named = fs.readFileSync(namingFile, 'utf8').trim();
  const fixtureDirectory = path.resolve(skillDirectory, named);
  const fixturesRoot = path.join(skillDirectory, 'evals', 'fixtures');
  if (named === '' || !fixtureDirectory.startsWith(`${fixturesRoot}${path.sep}`)) {
    throw new StepFailure(`${skill}/${ARM_TREE_FIXTURE_FILE} must name a folder under evals/fixtures/, got: ${named}`, EXIT_REFUSED);
  }
  fs.mkdirSync(fixtureDirectory, { recursive: true });
  await extractTree(settings, commit, ['.', `:(exclude)${skill}/evals`], fixtureDirectory, run);
}

async function buildArm(settings, skill, arm, ref, commit, run) {
  const treeDirectory = path.join(settings.work, skill, arm);
  const skillDirectory = path.join(treeDirectory, skill);
  fs.mkdirSync(treeDirectory, { recursive: true });
  await extractTree(settings, commit, ['.', `:(exclude)${skill}/evals`], treeDirectory, run);
  if (!fs.statSync(skillDirectory, { throwIfNoEntry: false })?.isDirectory()) {
    throw new StepFailure(`${skill} is not a folder in ${ref}`, EXIT_REFUSED);
  }
  await extractTree(settings, settings.commits.head, [`${skill}/evals`], treeDirectory, run);
  await fillArmTreeFixture(settings, skill, commit, skillDirectory, run);
  const hasBaselineEval = fs.existsSync(path.join(skillDirectory, 'evals', 'baseline.eval.yaml'));
  const evalFile = arm === 'baseline' && hasBaselineEval ? 'evals/baseline.eval.yaml' : 'evals/eval.yaml';
  const outputDirectory = path.join(settings.out, skill, arm);
  fs.mkdirSync(outputDirectory, { recursive: true });
  const line = `skill=${skill} arm=${arm} ref=${ref} commit=${commit} eval-file=${evalFile} eval-commit=${settings.commits.head}`;
  return { skill, arm, line, evalFile, skillDirectory, outputDirectory };
}

async function buildArms(settings, run) {
  const arms = [];
  for (const skill of settings.skills) {
    arms.push(await buildArm(settings, skill, 'with-change', settings.source, settings.commits.source, run));
    arms.push(await buildArm(settings, skill, 'baseline', settings.baseline, settings.commits.baseline, run));
  }
  fs.writeFileSync(path.join(settings.out, 'arms.txt'), `${arms.map((arm) => arm.line).join('\n')}\n`);
  return arms;
}

function refuseEnvironmentFiles(arms) {
  for (const arm of arms) {
    const planted = SKILLED_CONFIGURATION_FILES.find((name) => fs.existsSync(path.join(arm.skillDirectory, name)));
    if (planted) throw new StepFailure(`the ${arm.arm} tree of ${arm.skill} holds a ${planted} file at the skill root, which skillEd would read`, EXIT_REFUSED);
  }
}

function throwIfInterrupted(run) {
  if (run.interrupted) throw new StepFailure(`interrupted by ${run.interrupted.signal}`, run.interrupted.exitCode);
}

async function validateArm(settings, arm, skilledPath, run) {
  const steps = [
    ['validate-skill', ['validate', '--skill', '.']],
    ['validate-eval', ['validate', arm.evalFile]],
    ['dry-run', ['run', arm.evalFile, '--dry-run']],
  ];
  for (const [label, args] of steps) {
    throwIfInterrupted(run);
    const outputFile = path.join(arm.outputDirectory, `${label}.txt`);
    const result = await execute(skilledPath, args, { cwd: arm.skillDirectory, env: skilledEnvironment(settings, { withKey: false }), outputFile, run });
    if (!succeeded(result)) {
      throw new StepFailure(`skillEd ${label} failed for ${arm.skill} ${arm.arm}; output in ${outputFile}`, EXIT_VALIDATION_FAILED);
    }
  }
}

async function runEgress(subcommand, outputFile, run) {
  return execute('sh', [EGRESS_SCRIPT, subcommand], { outputFile, run });
}

async function raiseEgress(settings, run) {
  throwIfInterrupted(run);
  const raised = await runEgress('up', path.join(settings.out, 'egress-up.txt'), run);
  run.egressRaised = raised.status === 0 || raised.status === EGRESS_UP_FAILED_AFTER_CHANGE;
  if (!succeeded(raised)) throw new StepFailure('egress up failed', EXIT_EGRESS_UP_FAILED);
  const probe = await runEgress('probe', path.join(settings.out, 'egress-probe.txt'), run);
  if (!succeeded(probe)) throw new StepFailure('the egress probe did not show the allowlist', EXIT_PROBE_FAILED);
}

function recordFailure(run, exitCode) {
  if (run.status === EXIT_OK) run.status = exitCode;
}

function readCaseResults(resultFile) {
  try {
    return JSON.parse(fs.readFileSync(resultFile, 'utf8')).case_results;
  } catch {
    return null;
  }
}

function resultGapOf(arm, iterations) {
  for (let iteration = 1; iteration <= iterations; iteration += 1) {
    const resultFile = path.join(arm.outputDirectory, `iteration-${iteration}`, 'result.json');
    const caseResults = readCaseResults(resultFile);
    if (!Array.isArray(caseResults)) return `${resultFile} is missing or unreadable`;
    if (caseResults.length === 0) return `${resultFile} holds no case`;
    const unjudged = caseResults.find((caseResult) => caseResult?.status !== 'PASS' && caseResult?.status !== 'FAIL');
    if (unjudged) return `case ${unjudged?.case_id} in ${resultFile} has status ${unjudged?.status}`;
  }
  return null;
}

async function realRun(settings, arm, run) {
  const args = ['run', arm.evalFile, '--provider', 'anthropic', '--model', settings.model, '--iteration', settings.iterations,
    '--output-dir', arm.outputDirectory, '--format', 'html', '--format', 'junit', '--event-log', path.join(arm.outputDirectory, 'events.jsonl')];
  const result = await execute(run.skilledPath, args, {
    cwd: arm.skillDirectory,
    env: skilledEnvironment(settings, { withKey: true }),
    timeoutMs: Number(settings.iterations) * Number(settings.secondsPerIteration) * 1000,
    outputFile: path.join(arm.outputDirectory, 'run.txt'),
    run,
  });
  if (result.timedOut && !run.interrupted) reportProblem(`the watchdog stopped ${arm.skill} ${arm.arm} after ${settings.iterations} iterations of ${settings.secondsPerIteration} seconds`);
  const gap = resultGapOf(arm, Number(settings.iterations));
  if (gap) {
    reportProblem(`${arm.skill} ${arm.arm} did not complete: ${gap}`);
    recordFailure(run, EXIT_RUN_INCOMPLETE);
  }
}

async function realRuns(settings, arms, run) {
  for (const arm of arms) {
    throwIfInterrupted(run);
    report(`run ${arm.skill} ${arm.arm}`);
    await realRun(settings, arm, run);
  }
}

async function removeSkilledContainers(run) {
  const names = await listSkilledContainers(run);
  for (const name of names) {
    const removal = await execute('docker', ['rm', '-f', name], { run });
    if (!succeeded(removal)) recordFailure(run, statusOf(removal));
  }
}

async function bringEgressDown(settings, run) {
  await runEgress('status', path.join(settings.out, 'egress-status.txt'), run);
  if (!run.egressRaised) return;
  const down = await runEgress('down', path.join(settings.out, 'egress-down.txt'), run);
  if (!succeeded(down)) recordFailure(run, statusOf(down));
}

async function scanForLeaks(settings, run) {
  const reportPath = path.join(settings.out, 'leak-scan.txt');
  const args = [LEAK_SCAN_SCRIPT, '--report', reportPath, settings.out, settings.work];
  const result = await execute(process.execPath, args, { input: `${settings.apiKey}\n`, run });
  process.stdout.write(result.stdout);
  process.stderr.write(result.stderr);
  return succeeded(result);
}

function listRegularFiles(root, directory = root) {
  const found = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) found.push(...listRegularFiles(root, full));
    else if (entry.isFile()) found.push(path.relative(root, full));
  }
  return found;
}

function writeChecksums(out) {
  const files = listRegularFiles(out).filter((file) => file !== 'SHA256SUMS.txt');
  files.sort((left, right) => Buffer.compare(Buffer.from(left), Buffer.from(right)));
  const lines = files.map((file) => `${sha256Of(path.join(out, file))}  ${file}`);
  fs.writeFileSync(path.join(out, 'SHA256SUMS.txt'), `${lines.join('\n')}\n`);
}

async function moveWorkToTrash(settings, run) {
  const result = await execute('trash', [settings.work], { run });
  if (!succeeded(result)) recordFailure(run, statusOf(result));
}

async function attempt(label, run, step) {
  try {
    await step();
  } catch (error) {
    reportProblem(`${label} failed: ${error.message}`);
    recordFailure(run, 1);
  }
}

async function cleanUp(settings, run) {
  run.cleaningUp = true;
  await attempt('removing containers', run, () => removeSkilledContainers(run));
  await attempt('taking egress down', run, () => bringEgressDown(settings, run));
  let scanPassed = false;
  await attempt('the leak scan', run, async () => {
    scanPassed = await scanForLeaks(settings, run);
  });
  await attempt('writing SHA256SUMS.txt', run, async () => writeChecksums(settings.out));
  if (scanPassed) await attempt('moving the work folder to the Trash', run, () => moveWorkToTrash(settings, run));
  return scanPassed;
}

function installSignalHandlers(run) {
  for (const signal of HANDLED_SIGNALS) {
    process.on(signal, () => {
      run.signalsReceived += 1;
      if (run.signalsReceived > 1) {
        for (const group of run.children) group.kill();
        return;
      }
      if (run.cleaningUp) return;
      run.interrupted = { signal, exitCode: EXIT_SIGNAL_BASE + os.constants.signals[signal] };
      for (const group of run.children) group.terminate();
    });
  }
}

async function runSteps(settings, run) {
  fs.mkdirSync(settings.out, { recursive: true });
  fs.mkdirSync(settings.work);
  run.skilledPath = settings.skilled ?? (await downloadSkilled(settings, run));
  const arms = await buildArms(settings, run);
  refuseEnvironmentFiles(arms);
  for (const arm of arms) await validateArm(settings, arm, run.skilledPath, run);
  await raiseEgress(settings, run);
  await realRuns(settings, arms, run);
}

async function runEvaluation(settings) {
  const run = { status: EXIT_OK, interrupted: null, cleaningUp: false, signalsReceived: 0, egressRaised: false, children: new Set(), skilledPath: null };
  installSignalHandlers(run);
  try {
    await runSteps(settings, run);
  } catch (error) {
    reportProblem(error instanceof StepFailure ? error.message : `unexpected failure: ${error.message}`);
    recordFailure(run, error instanceof StepFailure ? error.exitCode : 1);
  }
  const scanPassed = await cleanUp(settings, run);
  if (!scanPassed) reportProblem(`the leak scan did not pass; the work folder stays at ${settings.work}`);
  report(`results in ${settings.out}`);
  if (!scanPassed) return EXIT_LEAK_SCAN;
  return run.interrupted ? run.interrupted.exitCode : run.status;
}

async function main(argv) {
  const options = parseOptions(argv);
  if (options.help) {
    process.stdout.write(USAGE);
    return EXIT_OK;
  }
  const settings = await checkPreconditions(options);
  return runEvaluation(settings);
}

main(process.argv.slice(2)).then(
  (exitCode) => process.exit(exitCode),
  (error) => {
    reportProblem(error instanceof Refusal ? error.message : `unexpected failure: ${error.message}`);
    process.exit(error instanceof Refusal ? error.exitCode : 1);
  },
);
