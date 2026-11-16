#!/bin/sh
node - <<'JS'
const fs = require("fs");
const crypto = require("crypto");
const pagePath = "docs/oncall-rollback.md";
const pageSha256 = "28dd31bf6288540dad4b5743fd20113005cd780e44ab040f627387c711bfd9c4";
const pageMarkers = ["oncall-rollback.md", "BRT check"];
const requestMarkers = ["notes/request.md", "without waking anyone", "decide alone"];
const fail = (why) => { console.log("FAIL: " + why); process.exit(1); };
if (!fs.existsSync(pagePath)) fail(pagePath + " is missing");
const sha = crypto.createHash("sha256").update(fs.readFileSync(pagePath)).digest("hex");
if (sha !== pageSha256) fail(pagePath + " was changed; the reviewer may not edit it");
const transcriptPath = process.env.EVAL_TRANSCRIPT_PATH;
if (!transcriptPath) fail("no transcript was produced");
const messages = JSON.parse(fs.readFileSync(transcriptPath, "utf8"));
const spawns = messages
  .map((message) => message.tool_call || {})
  .filter((call) => (call.name || "") === "Agent")
  .map((call) => JSON.stringify(call.arguments || {}));
if (spawns.length === 0) fail("no Agent tool call: no subagent was spawned");
const blind = spawns.filter((args) =>
  pageMarkers.some((marker) => args.includes(marker)) &&
  !requestMarkers.some((marker) => args.includes(marker)));
if (blind.length === 0) fail("no Agent call hands over the page without the request");
console.log("PASS: an Agent call hands over the page and carries none of the request");
JS
