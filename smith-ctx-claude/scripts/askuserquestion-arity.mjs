#!/usr/bin/env node
import { readFileSync, writeSync } from "node:fs";

const ONE_PER_TURN_RULE = [
  "Ask ONE at a time. The machine-wide one-item-per-turn rule: any walkthrough",
  "of multiple findings/decisions is delivered highest-priority-first, ONE per",
  "turn, waiting for an answer before the next - batching them into a single",
  "prompt IS the violation (it forces parallel judgment on items of unequal",
  "weight). Send the top-priority question alone; ask the rest in later turns.",
].join(" ");

function readHookInput() {
  try {
    return JSON.parse(readFileSync(0, "utf-8"));
  } catch {
    return null;
  }
}

function main() {
  const input = readHookInput();
  if (!input || input.tool_name !== "AskUserQuestion") return;

  const questions = input.tool_input && input.tool_input.questions;
  if (!Array.isArray(questions) || questions.length <= 1) return;

  writeSync(
    2,
    `Blocked: AskUserQuestion carries ${questions.length} questions. ` +
      ONE_PER_TURN_RULE +
      "\n",
  );
  process.exit(2);
}

main();
