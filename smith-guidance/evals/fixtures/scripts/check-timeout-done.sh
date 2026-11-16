#!/bin/sh
node - <<'JS'
const fs = require("fs");
const { spawnSync } = require("child_process");
const secondsOf = [["90s", 90], ["2m", 120], ["1h", 3600]];
const fail = (why) => { console.log("FAIL: " + why); process.exit(1); };
const run = (args) => spawnSync(process.execPath, args, { encoding: "utf8", timeout: 10000 });
const evaluate = (code) => run(["-e", code]).stdout.trim();
for (const file of ["src/durations.js", "cli/main.js"]) {
  if (!fs.existsSync(file)) fail(file + " is missing");
}
for (const [text, seconds] of secondsOf) {
  const got = evaluate("console.log(String(require('./src/durations.js').parseDuration('" + text + "')))");
  if (got !== String(seconds)) fail("parseDuration('" + text + "') must return " + seconds + ", got: " + got);
}
const badInput = evaluate(
  "try { console.log('returned ' + String(require('./src/durations.js').parseDuration('5x'))); }" +
  " catch (error) { console.log('threw ' + (error instanceof Error) + ' ' + error.message); }");
if (!badInput.startsWith("threw true") || !badInput.includes("5x")) {
  fail("parseDuration('5x') must throw an Error whose message contains 5x, got: " + badInput);
}
const valid = run(["cli/main.js", "--timeout", "2m"]);
if (valid.status !== 0 || !valid.stdout.split("\n").includes("timeout: 120")) {
  fail("`--timeout 2m` must exit 0 and print the line 'timeout: 120'");
}
const greeting = run(["cli/main.js", "--name", "Ada"]);
if (greeting.status !== 0 || !greeting.stdout.includes("hello Ada")) {
  fail("`--name Ada` must still print 'hello Ada'");
}
const invalid = run(["cli/main.js", "--timeout", "5x"]);
if (invalid.status !== 2) fail("`--timeout 5x` must exit with status 2, got status " + invalid.status);
if (!invalid.stderr.split("\n").some((line) => line.startsWith("error: "))) {
  fail("`--timeout 5x` must print one line starting with 'error: ' to stderr");
}
if (/^\s+at /m.test(invalid.stdout + invalid.stderr)) fail("`--timeout 5x` must not show a stack trace");
console.log("PASS: --timeout works and parseDuration throws on input it cannot read");
JS
