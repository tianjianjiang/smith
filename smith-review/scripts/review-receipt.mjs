#!/usr/bin/env node
import { receiptState, reviewedChange, writeReviewReceipt } from "./lib/review-receipt.mjs";

const USAGE = [
  "usage:",
  "  review-receipt.mjs write \"<plugin-pass receipt line>\" [--base <ref>]",
  "  review-receipt.mjs check [--base <ref>]",
  "",
  "The receipt names the combined diff of HEAD against its merge base with",
  "<ref> (default origin/HEAD). check prints the review-converged line of",
  "/smith-preflight and exits 0 on PASS, 1 on FAIL.",
].join("\n");
const BASE_OPTION = "--base";

function baseOption(commandArguments) {
  const index = commandArguments.indexOf(BASE_OPTION);
  return index === -1 ? null : commandArguments[index + 1] || "";
}

function check(directory, base) {
  const change = reviewedChange(directory, base);
  if (change.problem) return [`review-converged FAIL:${change.problem}`, 1];
  if (change.dirty) return ["review-converged FAIL:uncommitted changes the receipt cannot name", 1];
  const state = receiptState(change);
  const subject = `diff of HEAD against ${change.base} (${change.changeId.slice(0, 12)})`;
  if (state === "present") return [`review-converged PASS — receipt for the ${subject}`, 0];
  return [`review-converged FAIL:receipt ${state} for the ${subject}; run /smith-review to convergence`, 1];
}

function main(commandArguments) {
  const [command, line] = commandArguments;
  const directory = process.cwd();
  const base = baseOption(commandArguments);
  if (base === "") throw new Error(`${BASE_OPTION} needs a ref`);
  if (command === "write" && typeof line === "string" && line !== BASE_OPTION) {
    const change = writeReviewReceipt(directory, line, base);
    console.log(`review receipt written for the diff of HEAD against ${change.base} (${change.changeId.slice(0, 12)})`);
    return 0;
  }
  if (command === "check") {
    const [verdict, exitCode] = check(directory, base);
    console.log(verdict);
    return exitCode;
  }
  console.error(USAGE);
  return 2;
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (error) {
  console.error(error.message);
  process.exitCode = 2;
}
