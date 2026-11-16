import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { git } from "../../../smith-git/scripts/lib/hook-utils.mjs";

function fileSha256(path) {
  try {
    return createHash("sha256").update(readFileSync(path)).digest("hex");
  } catch {
    return "unknown";
  }
}

const REPOSITORY_OVERRIDES = ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY"];

function environmentWithoutRepositoryOverrides() {
  const environment = { ...process.env };
  for (const name of REPOSITORY_OVERRIDES) delete environment[name];
  return environment;
}

export function checkoutProvenance(checkoutRoot, hookPath) {
  const options = { failOpen: true, env: environmentWithoutRepositoryOverrides() };
  const commit = git(checkoutRoot, ["rev-parse", "HEAD"], options);
  const status = git(checkoutRoot, ["status", "--porcelain", "--untracked-files=all"], options);
  return {
    commit: commit || "unknown",
    treeIsDirty: status === null ? null : status !== "",
    hookSha256: fileSha256(hookPath),
  };
}

export function provenanceWasRead({ commit, treeIsDirty, hookSha256 }) {
  return commit !== "unknown" && treeIsDirty !== null && hookSha256 !== "unknown";
}
