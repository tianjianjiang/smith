#!/usr/bin/env node
import { lstatSync, readFileSync } from "node:fs";
import { isAbsolute } from "node:path";
import { blockWithError, readHookInput } from "../../smith-git/scripts/lib/hook-utils.mjs";
import { commandSegments } from "../../smith-git/scripts/lib/git-command-tokenizer.mjs";
import { attributionProblems, expectedAttribution, rejectionText } from "../../smith-style/scripts/lib/attribution.mjs";
import { classifyCommand, classifyTool } from "../../smith-style/scripts/lib/attribution-signatures.mjs";
import { ghApiPrTextAction, withAttachedFlagsSplit } from "./lib/gh-command.mjs";
import { commandReadings, invocationsOf } from "./lib/shell-scan.mjs";
import { commandExpands } from "./lib/write-payload.mjs";

const PROGRAMS = ["git", "gh"];
const SHELL_EXPANSION = /[$`]/;
const MENTIONS_A_PROGRAM = /\b(git|gh)\b/;

function recognizers(expands) {
  return {
    "gh-api-pull-request-text": (tokens) => {
      const action = ghApiPrTextAction(withAttachedFlagsSplit(tokens), expands);
      return Boolean(action) && action.action !== "delete";
    },
  };
}

function readPayloadFile(path, expands, singleStep) {
  if (!isAbsolute(path)) return { unreadable: `a draft file named by a relative path ('${path}'); pass its absolute path` };
  if (expands && SHELL_EXPANSION.test(path)) return { unreadable: "a draft file path built by shell expansion" };
  if (!singleStep) {
    return {
      unreadable:
        "a draft file read by a command that also runs other steps or expands anything, which may change it first; run the write as a command of its own",
    };
  }
  try {
    if (!lstatSync(path).isFile()) return { unreadable: `'${path}' is not a regular file` };
    return { text: readFileSync(path, "utf-8") };
  } catch {
    return { unreadable: `draft file '${path}' cannot be read` };
  }
}

function payloadText(payload, expands, singleStep) {
  if (payload.from === "file") return readPayloadFile(payload.value, expands, singleStep);
  if (payload.from === "literal" && expands) {
    return { unreadable: "a text in a command that expands anything, which may change the text gh receives; use a single-quoted literal" };
  }
  return { text: payload.value };
}

function check(write, sessionId, readText) {
  if (!write) return;
  const attribution = expectedAttribution(sessionId);
  if (write.unmatched) {
    const problems = ["it does not match a declared write signature", ...(write.hint ? [write.hint] : [])];
    blockWithError(rejectionText(write.subject, problems, attribution.expected));
  }
  if (!write.payload) return;
  const { text, unreadable } = readText(write.payload);
  if (unreadable) blockWithError(rejectionText(write.subject, [`its text cannot be read: ${unreadable}`], attribution.expected));
  const problems = attributionProblems(text, attribution);
  if (problems.length > 0) blockWithError(rejectionText(write.subject, problems, attribution.expected));
}

function checkCommand(command, sessionId) {
  const readings = commandReadings(command);
  if (readings === null) {
    if (MENTIONS_A_PROGRAM.test(command)) blockWithError("Blocked: the command nests shell wrappers too deeply for the attribution guard to read.");
    return;
  }
  const expands = commandExpands(command);
  const singleStep =
    !expands && commandSegments(command).length <= 1 && readings.every((simpleCommands) => simpleCommands.length <= 1);
  const commandRecognizers = recognizers(expands);
  for (const simpleCommands of readings) {
    for (const program of PROGRAMS) {
      for (const tokens of invocationsOf(program, simpleCommands)) {
        const write = classifyCommand(tokens, commandRecognizers);
        check(write, sessionId, (payload) => payloadText(payload, expands, singleStep));
      }
    }
  }
}

function main() {
  const input = readHookInput();
  if (!input) return;
  try {
    const command = input.tool_input && input.tool_input.command;
    if (input.tool_name === "Bash" || (input.tool_name === undefined && typeof command === "string")) {
      if (typeof command === "string") checkCommand(command, input.session_id);
      return;
    }
    if (typeof input.tool_name === "string") {
      check(classifyTool(input.tool_name, input.tool_input), input.session_id, (payload) => ({ text: payload.value }));
    }
  } catch (error) {
    blockWithError(`Attribution guard failed, so the call is blocked: ${error && error.message ? error.message : error}`);
  }
}

main();
