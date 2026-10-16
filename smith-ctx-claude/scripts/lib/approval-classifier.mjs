import { writeSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";

const CLASSIFIER_BIN = process.env.SMITH_APPROVAL_CLASSIFIER_BIN || "claude";
const CLASSIFIER_MODEL = process.env.SMITH_APPROVAL_CLASSIFIER_MODEL || "haiku";
const CLASSIFIER_TIMEOUT_MS = Number(process.env.SMITH_APPROVAL_CLASSIFIER_TIMEOUT_MS) || 30000;
const CLASSIFIER_REENTRY_ENV = "SMITH_APPROVAL_CLASSIFIER";

export function isClassifierReentry() {
  return process.env[CLASSIFIER_REENTRY_ENV] === "1";
}

export function classify({ hookName, fallback, systemPrompt, input, labels }) {
  const warn = (cause, detail) =>
    writeSync(2, `${hookName}: approval classifier ${cause}, falling back to ${fallback}: ${detail}\n`);
  const result = spawnSync(
    CLASSIFIER_BIN,
    [
      "-p",
      "--model",
      CLASSIFIER_MODEL,
      "--system-prompt",
      systemPrompt,
      "--tools",
      "",
      "--strict-mcp-config",
      "--mcp-config",
      '{"mcpServers":{}}',
      "--setting-sources",
      "",
    ],
    {
      input,
      encoding: "utf8",
      cwd: tmpdir(),
      timeout: CLASSIFIER_TIMEOUT_MS,
      env: { ...process.env, [CLASSIFIER_REENTRY_ENV]: "1" },
    },
  );
  if (result.error || result.status !== 0 || typeof result.stdout !== "string") {
    const reason = (result.error && result.error.message) || `exit ${result.status}`;
    const stderr = (result.stderr || "").trim();
    warn("unavailable", stderr ? `${reason}: ${stderr.slice(0, 300)}` : reason);
    return null;
  }
  const verdict = result.stdout.trim().toLowerCase();
  if (!labels.includes(verdict)) {
    warn("returned unexpected output", JSON.stringify(verdict.slice(0, 100)));
    return null;
  }
  return verdict;
}
