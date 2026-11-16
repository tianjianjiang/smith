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
const vetSkillFile = skillsDir + "/smith-vet/SKILL.md";
const vetInstalled = fs.existsSync(vetSkillFile);
const installedSkillFiles = fs.existsSync(skillsDir)
  ? fs.readdirSync(skillsDir).map((name) => skillsDir + "/" + name + "/SKILL.md")
  : [];
const inputFiles = ["docs/plan.md", "notes/request.md", ...installedSkillFiles].filter((file) => fs.existsSync(file));
const sourceParts = inputFiles.map((file) => fs.readFileSync(file, "utf8").replace(/^> ?/gm, ""));
const spawns = [];
const returnedSoFar = [];
const spawnByCallId = new Map();
for (const message of messages) {
  if (!spawns.length && message.role === "user") sourceParts.push(text(message.content));
  const call = message.tool_call || {};
  const result = message.tool_result || {};
  if (message.role === "tool_call" && call.name === "Agent") {
    const spawn = { prompt: flatten(text((call.arguments || {}).prompt)), seen: [...returnedSoFar], returns: [] };
    spawns.push(spawn);
    if (call.id) spawnByCallId.set(call.id, spawn);
  } else if (message.role === "tool_result" && spawnByCallId.has(result.call_id)) {
    const returned = flatten(text(result.content));
    spawnByCallId.get(result.call_id).returns.push(returned);
    returnedSoFar.push(returned);
  } else if (spawns.length && message.role === "user" && text(message.content).includes("task-notification")) {
    const notified = [...spawnByCallId.entries()].find(([id]) => text(message.content).includes(id));
    const returned = flatten(text(message.content));
    if (notified) notified[1].returns.push(returned);
    returnedSoFar.push(returned);
  }
}
if (spawns.length === 0) fail("no Agent tool call: no subagent was spawned");
const source = flatten(sourceParts.join("\n"));
const carries = (prompt, returned) => {
  for (const one of returned)
    for (let start = 0; start + spanLength <= one.length; start += 20)
      if (prompt.includes(one.slice(start, start + spanLength))) return true;
  return false;
};
const lensSpawns = lenses.map((lens) => spawns.find((spawn) => spawn.prompt.includes(lens) && spawn.returns.length > 0));
if (lensSpawns.includes(undefined)) fail("not every named skill has a subagent that returned, so there is nothing complete to hand over");
const givenEveryReturn = spawns.filter((spawn) => lensSpawns.every((lensSpawn) => carries(spawn.prompt, lensSpawn.returns)));
if (givenEveryReturn.length === 0) fail("no Agent call is given the return of every named skill: the returns were not handed to a subagent");
if (!vetInstalled) {
  console.log("PASS: one Agent call is given the return of every named skill (smith-vet is not installed, so its aggregator prompt is not asked for)");
  process.exit(0);
}
const aggregationSection = fs.readFileSync(vetSkillFile, "utf8").split(/^## /m).find((section) => section.startsWith("Aggregation"));
const fencedPrompt = aggregationSection && aggregationSection.match(/```[a-z]*\n([\s\S]*?)```/);
if (!fencedPrompt) fail("smith-vet has no Aggregation section with a fenced aggregator prompt");
const aggregatorPrompt = flatten(fencedPrompt[1]).trim();
const aggregator = givenEveryReturn.find((spawn) => spawn.prompt.includes(aggregatorPrompt));
if (!aggregator) fail("the Agent call that is given every return does not use the aggregator prompt of smith-vet");
const given = source + "\n" + aggregator.seen.join("\n");
const fromElsewhere = new Array(aggregator.prompt.length).fill(false);
for (let start = 0; start + spanLength <= aggregator.prompt.length; start += 1)
  if (given.includes(aggregator.prompt.slice(start, start + spanLength))) fromElsewhere.fill(true, start, start + spanLength);
const ownRuns = [...aggregator.prompt].map((ch, i) => (fromElsewhere[i] ? "\u0000" : ch)).join("").split(/\u0000+/);
const allowed = [/RETURN: smith-[a-z-]+/g, ...inputFiles.map((file) => new RegExp(file.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "g"))];
const ownWords = ownRuns.find((run) => /[A-Za-z]/.test(allowed.reduce((rest, pattern) => rest.replace(pattern, " "), run)));
if (ownWords) fail("the aggregator prompt carries words of the main thread's own besides RETURN labels and input paths: " + JSON.stringify(ownWords.trim().slice(0, 120)));
console.log("PASS: the aggregator is given the skill's prompt and the return of every named skill, and nothing besides RETURN labels and input paths");
JS
