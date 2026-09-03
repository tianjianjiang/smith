# Hooks Reference — smith-standards

Detailed behavior for the guard hook whose script lives under
`smith-standards/scripts/`. See the repo root `README.md` "Hooks" section for
the cross-skill summary table, the full `settings.json` registration block,
and the manual verification checklist. `smith-ctx-claude/references/HOOKS.md`
and `smith-git/references/HOOKS.md` cover hooks owned by those skills.

## Overview

| Hook | Event (matcher) | Blocks / Advisory |
|---|---|---|
| `inline-comment-lint.mjs` | PreToolUse (`Edit\|Write\|NotebookEdit`) | Advisory: flags any inline comment added to a code file |

## inline-comment-lint

**inline-comment-lint** (`smith-standards/scripts/inline-comment-lint.mjs`)
— PreToolUse guard (matcher `Edit|Write|NotebookEdit`) that, for code files
only, counts the **comment blocks** a single edit adds and emits an
**advisory** reminder of `smith-standards/SKILL.md:29-33` (NEVER add inline
comments) when ANY inline comment is detected. Advisory only — it never blocks.
Supported languages: Python, Bash, JavaScript/TypeScript, C/C++ (17 file
extensions: .js, .mjs, .cjs, .ts, .mts, .cts, .tsx, .jsx, .c, .h, .cc, .cpp,
.hpp, .py, .sh, .bash, .zsh). By design
it detects only full-line comments — trailing comments and cross-line constructs
(multi-line template literals, block comments spanning lines) are intentionally
NOT parsed, keeping the heuristic simple until a real per-language linter
replaces it. Shebangs are exempt (scripts only); config, `.md`, and `.json`
files are out of scope.

Test suite: `smith-standards/scripts/tests/run-all.sh`.
