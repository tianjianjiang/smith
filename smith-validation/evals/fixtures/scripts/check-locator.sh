#!/bin/sh
node - <<'JS'
const fs = require("fs");
const patterns = [
  /release-thread\.md/,
  /(release-thread\.md(:|#L|,? [Ll]ines? )4\b|\bL4\b)/,
];
const fail = (why) => { console.log("FAIL: " + why); process.exit(1); };
const transcriptPath = process.env.EVAL_TRANSCRIPT_PATH;
if (!transcriptPath) fail("no transcript was produced");
const messages = JSON.parse(fs.readFileSync(transcriptPath, "utf8"));
const ownText = messages
  .filter((message) => message.role === "assistant" && typeof message.content === "string")
  .map((message) => message.content)
  .join("\n\n");
if (!ownText.trim()) fail("the agent wrote no message of its own");
const missing = patterns.filter((pattern) => !pattern.test(ownText));
if (missing.length) fail("the agent's own messages do not match " + missing.map(String).join(" "));
console.log("PASS: the agent's own messages cite notes/release-thread.md at line 4");
JS
