// serena-root.mjs - where Serena's project root is, as seen from a hook
//
// A hook payload carries no Serena state. Serena started with
// --project-from-cwd fixes its root once, at server start, as the nearest
// ancestor of the launch directory holding .serena/project.yml or .git
// (find_project_root in serena/cli.py, Serena 1.7.0). CLAUDE_PROJECT_DIR stays
// at the session's launch directory after EnterWorktree while the payload's
// cwd follows Claude into the worktree
// (https://code.claude.com/docs/en/hooks, retrieved 2026-09-28), so the same
// walk from CLAUDE_PROJECT_DIR reproduces Serena's root.
//
// A mismatch exists when the session cwd and Serena's root lie in different
// checkouts (the primary checkout or a linked worktree) of one repository,
// in either direction. Serena's root may lie below the top of its checkout
// (a .serena/project.yml in a subdirectory), so both are reported. A
// worktree that is still registered but whose directory is gone is ignored.
//
// Serena reads .gitignore files only, never .git/info/exclude or
// core.excludesFile, so reachability asks git about .gitignore files alone:
// probed with git 2.55.0 on 2026-09-28, git check-ignore reports the
// info/exclude rule of a parent directory and hides a .gitignore rule beneath
// it. A failed query counts as unreachable.
//
// Paths are compared in their real case (realpathSync.native), because the
// macOS file system accepts a launch directory typed in another case.
import { existsSync, realpathSync, statSync } from "node:fs";
import { basename, dirname, isAbsolute, join, relative, sep } from "node:path";
import { git } from "./hook-utils.mjs";

export const SERENA_TOOL_PREFIX = /^mcp__(plugin_serena_)?serena__/;

function isFile(path) {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

export function canonicalPath(path) {
  let existing = path;
  const missing = [];
  while (!existsSync(existing)) {
    const up = dirname(existing);
    if (up === existing) return path;
    missing.unshift(basename(existing));
    existing = up;
  }
  try {
    return join(realpathSync.native(existing), ...missing);
  } catch {
    return path;
  }
}

export function isInside(parent, child) {
  const rel = relative(parent, child);
  return rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel);
}

export function findSerenaProjectRoot(launchDir) {
  if (!launchDir || typeof launchDir !== "string" || !existsSync(launchDir)) {
    return "";
  }
  let dir = canonicalPath(launchDir);
  for (;;) {
    if (
      isFile(join(dir, ".serena", "project.yml")) ||
      existsSync(join(dir, ".git"))
    ) {
      return dir;
    }
    const up = dirname(dir);
    if (up === dir) return "";
    dir = up;
  }
}

function listWorktrees(dir) {
  const porcelain = git(dir, ["worktree", "list", "--porcelain"], {
    failOpen: true,
  });
  if (!porcelain) return [];
  return porcelain
    .split("\n")
    .filter((line) => line.startsWith("worktree "))
    .map((line) => canonicalPath(line.slice("worktree ".length)))
    .filter((worktree) => existsSync(worktree));
}

function reachableThroughGitignore(root, prefix) {
  const ignored = git(
    root,
    [
      "ls-files",
      "--others",
      "--ignored",
      "--exclude-per-directory=.gitignore",
      "--",
      prefix,
    ],
    { failOpen: true },
  );
  return ignored === "";
}

function checkoutTop(dir) {
  const top = git(dir, ["rev-parse", "--path-format=absolute", "--show-toplevel"], {
    failOpen: true,
  });
  return top ? canonicalPath(top) : "";
}

export function resolveCheckoutMismatch(cwd, launchDir) {
  if (!cwd || typeof cwd !== "string" || !existsSync(cwd)) return null;
  const root = findSerenaProjectRoot(launchDir);
  if (!root) return null;

  const sessionTop = checkoutTop(cwd);
  const rootTop = checkoutTop(root);
  if (!sessionTop || !rootTop || sessionTop === rootTop) return null;

  const worktrees = listWorktrees(cwd);
  if (!worktrees.includes(sessionTop) || !worktrees.includes(rootTop)) {
    return null;
  }

  const nested = isInside(root, sessionTop);
  const prefix = nested ? relative(root, sessionTop) : "";
  return {
    root,
    rootTop,
    sessionTop,
    prefix,
    otherWorktrees: worktrees.filter(
      (w) => w !== sessionTop && isInside(root, w) && w !== root,
    ),
    reachable: nested && reachableThroughGitignore(root, prefix),
  };
}
