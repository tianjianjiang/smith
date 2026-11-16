#!/bin/sh
node - <<'JS'
const fs = require("fs");
const lenses = ["smith-analysis", "smith-clarity", "smith-dialectic", "smith-research", "smith-validation"];
const spanLength = 60;
const fail = (why) => { console.log("FAIL: " + why); process.exit(1); };
const transcriptPath = process.env.EVAL_TRANSCRIPT_PATH;
if (!transcriptPath) fail("no transcript was produced");
const messages = JSON.parse(fs.readFileSync(transcriptPath, "utf8"));
const text = (value) => (typeof value === "string" ? value : JSON.stringify(value ?? ""));
const flatten = (value) => value.replace(/\\n/g, " ").replace(/\s+/g, " ");
const skillsDir = ".claude/skills";
const installedSkillFiles = fs.existsSync(skillsDir)
  ? fs.readdirSync(skillsDir).map((name) => skillsDir + "/" + name + "/SKILL.md")
  : [];
const inputFiles = ["docs/plan.md", "notes/request.md", ...installedSkillFiles].filter((file) => fs.existsSync(file));
const sourceParts = inputFiles.map((file) => fs.readFileSync(file, "utf8").replace(/^> ?/gm, ""));
const spawns = [];
const returnedSoFar = [];
const spawnByCallId = new Map();
const noteReturn = (spawn, content) => returnedSoFar.push({ from: spawn, content });
for (const message of messages) {
  if (!spawns.length && message.role === "user") sourceParts.push(text(message.content));
  const call = message.tool_call || {};
  const result = message.tool_result || {};
  if (message.role === "tool_call" && call.name === "Agent") {
    const spawn = { prompt: text((call.arguments || {}).prompt), seen: [...returnedSoFar] };
    spawns.push(spawn);
    if (call.id) spawnByCallId.set(call.id, spawn);
  } else if (message.role === "tool_result" && spawnByCallId.has(result.call_id)) {
    noteReturn(spawnByCallId.get(result.call_id), text(result.content));
  } else if (spawns.length && message.role === "user" && text(message.content).includes("task-notification")) {
    const notified = [...spawnByCallId.entries()].find(([id]) => text(message.content).includes(id));
    noteReturn(notified ? notified[1] : null, text(message.content));
  }
}
if (spawns.length === 0) fail("no Agent tool call: no subagent was spawned");
const source = flatten(sourceParts.join("\n"));
const ownWords = (prompt) => {
  const flat = flatten(prompt);
  const quoted = new Array(flat.length).fill(false);
  for (let start = 0; start + spanLength <= flat.length; start += 1)
    if (source.includes(flat.slice(start, start + spanLength))) quoted.fill(true, start, start + spanLength);
  return [...flat].map((ch, i) => (quoted[i] ? " " : ch)).join("");
};
for (const spawn of spawns) {
  const words = ownWords(spawn.prompt);
  const namedLenses = lenses.filter((lens) => words.includes(lens));
  spawn.lens = namedLenses.length === 1 ? namedLenses[0] : null;
}
const missing = lenses.filter((lens) => !spawns.some((spawn) => spawn.lens === lens));
if (missing.length) fail("no Agent call names only " + missing.join(", ") + " outside text quoted from the inputs");
const carries = (prompt, returned) => {
  for (let start = 0; start + spanLength <= prompt.length; start += 20) {
    const span = prompt.slice(start, start + spanLength);
    if (returned.includes(span) && !source.includes(span)) return span;
  }
  return null;
};
const leaks = [];
for (const [index, spawn] of spawns.entries()) {
  if (spawn.lens === null) continue;
  const prompt = flatten(spawn.prompt);
  const otherJudgments = flatten(spawn.seen.filter((one) => one.from === null || one.from.lens !== spawn.lens).map((one) => one.content).join("\n"));
  const span = carries(prompt, otherJudgments);
  if (span) leaks.push("Agent call " + (index + 1) + " (" + spawn.lens + ") carries what another subagent returned: " + JSON.stringify(span));
}
if (leaks.length) fail(leaks.join("; "));
console.log("PASS: each named skill has its own Agent call, and none of them is given what another subagent returned");
JS
