#!/usr/bin/env node
import {
  currentBranch,
  readLedger,
  scopeRootCandidates,
  verdictFor,
} from "./lib/spawn-ledger.mjs";

const cwd = process.argv[2] || process.cwd();
const branch = currentBranch(cwd);
const { verdict, detail } = verdictFor(
  readLedger(scopeRootCandidates(cwd), branch),
);

process.stdout.write(
  `subagent-contract ${verdict} — branch ${branch || "unknown"}: ${detail}\n`,
);
