#!/usr/bin/env node
import { readFileSync, createReadStream } from "node:fs";
import { createInterface } from "node:readline";

const CLAIMED_SKILL = /using @([a-z0-9-]+)/gi;

function claimedSkills(message) {
  const claimed = new Set();
  if (typeof message !== "string") return claimed;
  let match;
  CLAIMED_SKILL.lastIndex = 0;
  while ((match = CLAIMED_SKILL.exec(message)) !== null) {
    claimed.add(match[1].toLowerCase());
  }
  return claimed;
}

async function skillsInvokedThisTurn(transcriptPath) {
  const invoked = new Set();
  const lines = createInterface({
    input: createReadStream(transcriptPath, { encoding: "utf-8" }),
    crlfDelay: Infinity,
  });
  for await (const line of lines) {
    if (!line.trim()) continue;
    let event;
    try {
      event = JSON.parse(line);
    } catch {
      continue;
    }
    if (event && event.type === "user") {
      const blocks = event.message && event.message.content;
      const carriesToolResult =
        Array.isArray(blocks) &&
        blocks.some((block) => block && block.type === "tool_result");
      if (!carriesToolResult) invoked.clear();
      continue;
    }
    const content = event && event.message && event.message.content;
    if (!Array.isArray(content)) continue;
    for (const block of content) {
      if (block && block.type === "tool_use" && block.name === "Skill") {
        const skill = block.input && block.input.skill;
        if (typeof skill === "string") invoked.add(skill.toLowerCase());
      }
    }
  }
  return invoked;
}

function reminder(uninvoked) {
  const list = uninvoked.map((name) => `@${name}`).join(", ");
  return (
    `skill-claim-lint: you wrote "using ${list}" but did not invoke ` +
    `${uninvoked.length > 1 ? "them" : "it"} via the Skill tool this turn. USE ` +
    `a skill by invoking it (Skill tool), not by reading or mentioning it - ` +
    `reading the SKILL.md by hand is not using the skill.`
  );
}

async function main() {
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf-8"));
  } catch {
    return;
  }
  if (!input || typeof input !== "object") return;

  const claimed = claimedSkills(input.last_assistant_message);
  if (claimed.size === 0) return;

  const transcriptPath = input.transcript_path;
  if (typeof transcriptPath !== "string") return;

  let invoked;
  try {
    invoked = await skillsInvokedThisTurn(transcriptPath);
  } catch {
    return;
  }

  const uninvoked = [...claimed].filter((name) => !invoked.has(name));
  if (uninvoked.length === 0) return;

  process.stdout.write(
    JSON.stringify({ systemMessage: reminder(uninvoked) }) + "\n",
  );
}

main().catch(() => {});
