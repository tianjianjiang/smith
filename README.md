# Agent Smith

> AI agent skills that follow you everywhere, Mr. Anderson.

## Overview

Smith is a collection of **47 skills** for AI-assisted development, following the [agentskills.io specification](https://agentskills.io)[[29]](#ref-29) and [AGENTS.md standard](https://agents.md)[[28]](#ref-28).

**Features**:
- **Progressive disclosure**: Metadata at startup, full content on activation
- **Semantic activation**: Skills load based on task context
- **Cross-platform**: Works with 25+ AI coding tools

## Quick Start

```shell
git clone https://github.com/tianjianjiang/smith.git $HOME/.smith
```

### Link to your project

Claude Code global config:

```shell
ln -sf $HOME/.smith/AGENTS.md $HOME/.claude/CLAUDE.md
```

Or symlink to project root:

```shell
ln -sf $HOME/.smith/AGENTS.md ./AGENTS.md
```

### Claude Code Skills Directory

Symlink smith as Claude Code skills for automatic discovery:

```shell
ln -sf $HOME/.smith $HOME/.claude/skills
```

Claude Code discovers skills and offers them based on task context. All skills use "smith-" prefix to avoid conflicts with built-in commands (`/context`, `/ide`, `/skills`, etc.).

### Hooks (manual registration)

Some scripts in this repo are hooks, NOT self-activating skills — they only
take effect once registered in `$HOME/.claude/settings.json` (see
`@smith-settings/SKILL.md`). With the skills symlink above in place, register
the hooks below.

- **skill-router** (`smith-ctx-claude/scripts/skill-router.mjs`) — advisory
  UserPromptSubmit router that surfaces candidate smith skills per prompt from
  `skill-triggers.json`.
- **branch-guard** (`smith-ctx-claude/scripts/branch-guard.mjs`) — PreToolUse
  guard that blocks file edits while a repo is on its default branch
  (`main`/`master`/`develop`): branch/worktree first. Per-repo opt-out: create
  `.claude/branch-guard.disabled` in that repo.
- **worktree-dirty-guard** (`smith-ctx-claude/scripts/worktree-dirty-guard.mjs`)
  — PreToolUse guard that blocks `EnterWorktree` while the checkout has
  uncommitted changes (they would not carry into the new worktree).

The hooks below are deterministic guards for recurring agent-discipline
mistakes (each mechanises a rule that prose alone kept failing to hold). They
all **fail open** — a parse or tool error inside a guard lets the call through,
so a guard bug never breaks unrelated work. Failing open on error is separate
from a guard's intended action on valid input: `askuserquestion-arity` blocks a
multi-question call, and `branch-rename-open-pr` blocks an unrecoverable rename
(or escalates to a prompt when it cannot verify PR state) rather than letting it
through.

- **external-write-guard** (`smith-ctx-claude/scripts/external-write-guard.mjs`)
  — PreToolUse guard (matchers `mcp__.*` and `Bash`) that escalates
  human-facing writes to a `permissionDecision:"ask"` prompt, so an external
  write cannot fire without a per-artifact yes. On the **MCP channel**: the
  human-facing write tools (Jira/Confluence create·edit·transition·comment,
  Notion create·update·move·duplicate, non-draft Slack sends). Read/search/fetch
  tools and every `*_draft` variant fall through untouched. The write set is a
  pre-compiled `const` in the script itself (its single source of truth). On
  the **Bash channel** (reusing `unwrappedCommandSegments` from
  `lib/git-command-tokenizer.mjs`, which layers `eval`/`sh -c`/`bash -c`
  (separate option flags before `-c`, e.g. `bash -e -c "..."`, AND clustered
  single-dash short flags ending in `c`, e.g. `bash -ec "..."`/`sh -xc "..."`,
  are both recognized, not just the bare `-c` form)/`command`-prefix
  (including POSIX `command -p`)/`sudo`/`nice`/`time`/`nohup`/`env`-prefix
  (including a leading `VAR=value` before the real command for `env`, and each
  wrapper's own common value-taking flags — `sudo -u`/`-g`/`-h`/`-p`/
  `--chdir`, `nice -n`, `time -f`/`--format`, `env -u`/`--chdir` — so the
  flag's value is never misread as the real command; `env -S`/`--split-string`
  is a special case, since its value is itself a shell-word-split
  mini-command-line, not an opaque value to skip — its whitespace-separated
  words become the real command and arguments, e.g. `env -S "git commit
  --amend"` correctly resolves to `git commit --amend`)/bare subshell-paren (`` (cmd) ``/`` ( cmd ) ``, including combined
  with another wrapper like `` (sudo cmd) `` or nested like `` ((cmd)) ``,
  recursively — each stripped paren layer consumes one level of the same
  depth budget as `eval`/`sh -c`, so a deeply-nested subshell fails closed the
  same way)/absolute-path unwrapping — ALL of the above compose freely with
  each other, in any order and any depth (e.g. `sudo sh -c '...'`, a wrapper
  followed by a shell, is fully unwrapped, not just the reverse `sh -c 'sudo
  ...'`), each layer consuming one level of the shared depth budget. A
  subshell containing a `;`/`&&`/`||`-joined compound command (e.g. `(cd /tmp
  && git commit --amend)`) is recognized as ONE balanced, quote-aware group at
  the string level BEFORE tokenization (not by naively splitting on those
  characters first and gluing the parens back on afterward), so its inner
  content is re-processed as its own independent command list — `cd /tmp` and
  `git commit --amend` both surface as their own detected segments, and
  whatever follows the closing paren (e.g. `&& echo done`) is still processed
  too. This inner re-processing works on the ORIGINAL raw string content, not
  a rejoin of already-dequoted tokens, so a quoted multi-word argument inside
  the parens (e.g. a commit message containing text that looks like a flag)
  survives as the single token it always was — unlike `eval`/`sh -c`, which DO
  rejoin already-split tokens with plain spaces before re-parsing, faithfully
  reproducing real bash's own loss of quote boundaries when `eval` is given
  multiple pre-split arguments (verified against real bash; this asymmetry
  between paren-handling and `eval`/`sh -c` is intentional, not an
  inconsistency — parens don't re-tokenize their content in real bash the way
  `eval` does, so this hook doesn't either). Clustered short flags are split
  at
  whichever character in the cluster is the first value-taking one (e.g.
  `gh pr merge -dR owner/repo` splits into `-d` and `-R owner/repo`, not one
  opaque `-dR` token), recursively up to 7 levels deep (an 8th nested wrap hits
  the depth limit and fails closed — see below), on top of the existing
  quote/escape-aware `commandSegments` tokenization, and normalizes flag
  position and attached/assignment forms — `-Xvalue`, `-X=value`,
  `--flag=value` — before matching; a command nested deeper than the unwrap
  limit fails CLOSED — treated as an external write requiring `ask` — rather
  than silently falling through unrecognized, since giving up on unwrapping
  is not evidence the command is safe. **Known gaps**: each wrapper's
  value-taking flags are modeled against its common/likely usage, not its full
  flag surface — `sudo`'s `-r`/`--role`/`-t`/`--type` (SELinux), and a bare
  `sudo VAR=value` (unlike `env`, `sudo` does not treat a leading
  `VAR=value` as an environment assignment by convention), are not recognized
  as consuming a value, so in those specific cases the value could be misread
  as the real command, silently missing the wrapped command underneath.
  `env -S`'s word-splitting only handles plain whitespace separation, not its
  documented backslash escape sequences or `${VAR}` substitution — an `-S`
  value relying on either of those is not evaluated the way real `env` would
  evaluate it, so the resulting "command" could differ from what real `env`
  would actually run; this is a narrow, shebang-line-oriented feature
  (`#!/usr/bin/env -S ...`), not common in interactive/agentic use):
  `gh pr comment`/`gh issue comment`
  (always), `gh pr review` when a submit flag is present (`-a/--approve`,
  `-c/--comment`, `-r/--request-changes`, including a clustered short form like
  `-ab`), `gh pr close`/`gh pr reopen`/`gh issue close`/`gh issue reopen` when
  a `-c`/`--comment`/attached `-cVALUE` value is present, `gh pr-review
  comments reply` (this repo's own documented review-thread-reply path,
  `@smith-gh-pr` "Posting Review Findings" — detected by the literal `reply`
  token appearing anywhere in the command, not by its position, so a
  documented-valid reordering like `gh pr-review comments --pr 1 reply ...`
  is still caught; `gh pr-review threads resolve`/`list` are not flagged —
  mechanics/read, same allowlist principle as `resolveReviewThread` below),
  `gh api` against an endpoint matching `/comments` or `/reviews` (with or without a
  trailing query string) when the request is a write (explicit
  `-X`/`--method` `POST/PUT/PATCH/DELETE`, or an implied `POST` from
  `-f`/`-F`/`--raw-field`/`--field`/`--input` not overridden by an explicit
  `--method GET` — verified
  against real `gh api` traffic via `GH_DEBUG=api`, not inferred from
  `gh api --help`'s silence on `--input`: an earlier draft of this guard
  wrongly excluded `--input` on that inference and a review round caught it),
  and `gh api graphql`/`gh api /graphql` whose query text names a
  comment/review/discussion write mutation from a fixed allowlist verified
  against GitHub's live GraphQL schema (`gh api graphql -f query='{ __type(name:
  "Mutation") { fields { name isDeprecated } } }'`) — every name in that
  allowlist is a real, explicit `const`, not an inferred pattern; anything not
  listed (including `resolveReviewThread`/`unresolveReviewThread`, mechanics
  per `@smith-guidance`'s External-writes split, and non-comment mutations)
  falls through unflagged by construction, not by semantic judgment. A global
  flag like `-R`/`--repo` may appear anywhere in the command (before or after
  the resource/subcommand) without defeating detection. A single Bash call
  chaining more than one detected write (e.g. `gh pr comment ... &&
  gh pr review ... --approve`) still triggers only one `ask` prompt — Claude
  Code intercepts the whole tool call, not each `gh` invocation separately —
  but the prompt names every write found across the whole command, not just
  the first, so approving it is an informed decision about all of them.

  **Known limitations** (verified, not assumed — each checked against real
  `gh`/shell behavior before being accepted as out of scope): true shell
  **command substitution and variable expansion** (`` gh $(echo pr) comment ``,
  `` X=comment; gh pr $X ``) cannot be resolved by a static hook without
  actually executing the untrusted substituted text, which the hook itself
  must not do — permanent, not a tracked-fixable gap. `gh api graphql`/`gh
  api /graphql` with the query sourced from a file (`-f`/`-F query=@file`) or
  a raw `--input file` body is flagged unconditionally, not scanned for a
  mutation name — the file content is opaque to the hook, so there is nothing
  for the mutation-name allowlist to match against, and "can't tell" is
  treated the same as the unwrap-depth-exceeded case above: `ask`, not
  silently pass. This means an opaque-sourced GraphQL *read* also prompts
  (a safe-direction false positive, not a bypass). PR/issue *creation* (`gh pr create`,
  `gh issue create`) and *edit* (`gh pr edit --body`, `gh issue edit --body`,
  `gh api -X PATCH .../issues/{n}` without a `/comments` or `/reviews` path
  segment) are both out of scope here — a separate, narrower future guard is
  planned for blocking `gh pr create --draft` before local review reaches
  convergence (CodeRabbit skips draft PRs); PR/issue *edit* coverage is not
  yet planned as its own item and should be before relying on this guard for
  PR/issue body edits. Other `gh` resources that can carry human-authored
  content — `gh release create/edit --notes`, `gh gist create/edit`, `gh repo
  edit --description` and similar — are NOT audited or covered here; this
  guard's scope is PR/issue comment, review, reply, and close/reopen comment
  only. `git push` remains uncovered — mechanics under `@smith-guidance`'s split, not
  content. `lib/git-command-tokenizer.mjs` is loaded via a `dynamic import()`
  inside the Bash-channel path only, not statically at the top of the file —
  a missing or malformed copy of that shared file therefore can't disable the
  MCP channel (which has no file dependency of its own) and, on the Bash
  channel specifically, is treated the same as the unwrap-depth-exceeded case
  above: fails CLOSED (`ask`), not open, since a tokenizer that can't load
  means the command can't be shown safe. Verified directly: renaming the
  shared file to simulate a missing copy still asks on a real MCP write and
  now also asks (rather than silently allowing) on a Bash write that would
  otherwise have matched.

- **askuserquestion-arity** (`smith-ctx-claude/scripts/askuserquestion-arity.mjs`)
  — PreToolUse guard (matcher `AskUserQuestion`) that blocks a call carrying
  more than one question object: one item per turn. Note this also blocks
  legitimate multi-question clarification; skip registering it if you want the
  tool's native 1–4-question behaviour.

- **volatile-artifact-guard** (`smith-ctx-claude/scripts/volatile-artifact-guard.mjs`)
  — Stop/SubagentStop/SessionEnd guard that streams the transcript and, if the
  session wrote files under volatile prefixes (`/tmp`, `~/Downloads`,
  `$CLAUDE_JOB_DIR/tmp`), prints an **advisory** `systemMessage` listing them so
  nothing durable is stranded before exit. Advisory only — it never blocks.

- **branch-rename-open-pr** (`smith-ctx-claude/scripts/branch-rename-open-pr.mjs`)
  — PreToolUse guard (matcher `Bash`) that blocks a `git branch -m`/`-M`/`--move`
  rename of a branch whose head still has an open PR (renaming closes the PR
  unrecoverably). If `gh` cannot verify PR state (error or timeout) it
  escalates to a permission prompt rather than silently allowing — because the
  action it guards is unrecoverable; when `gh` is not installed it allows
  (the check is not applicable).

- **branch-name-guard** (`smith-ctx-claude/scripts/branch-name-guard.mjs`)
  — PreToolUse guard (matcher `Bash`) that blocks `git checkout -b`/`-B`/
  `--orphan`, `git switch -c`/`-C`/`--create`/`--orphan`, `git branch <name>`/
  `-m`/`-M`/`--move`/`-c`/`-C`/`--copy`, `git stash branch`, and
  `git worktree add -b`/`-B` (short
  flags, jammed short flags like `-bname`, and `--long=value` forms all
  recognized) when the target name doesn't match the Conventional Branch
  pattern `type/description` (`@smith-style/SKILL.md` Branch Names) —
  lowercase type from the Conventional Commits set, kebab-case description
  (hyphen-separated segments that may contain dots, e.g.
  `chore/deps-node18.20-bump`), no underscores/uppercase/consecutive-hyphens
  — or contains `post-review`/`after-review`. The pattern and
  forbidden-substring list are
  pre-compiled `const`s in the script itself, so no external config can
  silently disable the check. Blocks with an auto-corrected suggestion
  (lowercase, `_`→`-`, collapsed hyphens) rather than a bare rejection.
  Skips names containing an unresolved shell substitution (`$VAR`, `` `cmd` ``)
  rather than validating the literal syntax. **Known limitation** (shared
  with `branch-rename-open-pr`/`gh-stack-guard`, which parse Bash command
  text the same way): it only sees the command as typed, so a name resolved
  through a git/shell alias, or a branch created through a non-Bash path
  (`EnterWorktree`, an IDE git panel, an external terminal) is not checked.
  Closing that gap would need a git-native hook (e.g. `pre-push`) validating
  the resolved ref instead of Bash-command text — tracked as a follow-up,
  not attempted here. `git branch`'s create/rename/copy/listing/upstream
  flags are classified by a single per-token scan (`branchTokenCategory`)
  that stops at the first recognized flag character, so a value-taking
  flag's attached value (e.g. `-umain`) is never rescanned as if its
  characters were further bundled flags. `checkout`/`switch`'s flag lists
  only recognize `-b`/`-B`/`-c`/`-C`/`--create`/`--orphan` as create
  signals — plain `git checkout <name>`/`git switch <name>` DWIM-creating a
  local branch from a single matching remote-tracking branch, and
  `--track`/`-t` against a remote ref, are not recognized as creates at
  all, so no validation happens on those paths; tracked as a follow-up,
  not attempted here.

- **comment-density-lint** (`smith-ctx-claude/scripts/comment-density-lint.mjs`)
  — PreToolUse guard (matcher `Edit|Write|NotebookEdit`) that, for code files
  only, counts the **full-line** comments a single edit adds and emits an
  **advisory** reminder of `smith-standards/SKILL.md:29-32` (prefer
  self-documenting code) when both thresholds in
  `smith-ctx-claude/comment-lint-config.json` are exceeded (default: at least 3
  comment lines AND over 25% of non-blank lines). Advisory only — it never
  blocks. It is deliberately advisory, not a block: a script can count comments
  deterministically but cannot judge whether a given comment is one of the cases
  `smith-standards` allows (config, TODO marker, complex algorithm, non-obvious
  business logic), so a hard block would false-fire on legitimate comments. By
  design it detects only full-line comments — trailing comments and cross-line
  constructs (multi-line template literals, block comments spanning lines) are
  intentionally NOT parsed, keeping the heuristic simple until a real
  per-language linter replaces it. Shebangs and marker comments
  (`TODO`/`FIXME`/`NOQA`/`eslint-disable`/`SPDX`/…) are exempt; config, `.md`,
  and `.json` files are out of scope.

- **coined-shorthand-lint** (`smith-ctx-claude/scripts/coined-shorthand-lint.mjs`)
  — PreToolUse guard (matcher `Edit|Write|NotebookEdit`) that emits an
  **advisory** when an edit introduces a cluster of meaningless coined labels
  matching `[A-Z][0-9]{1,2}` (e.g. `T1`, `S5`) — the internal index codes
  `smith-standards` says to replace with descriptive names. Fires at
  `minDistinctTokens` distinct labels (default 2) so an incidental single use is
  not flagged; genuinely-standard tokens go in
  `smith-ctx-claude/coined-shorthand-config.json`'s allowlist. Advisory only,
  never blocks (a script cannot tell a meaningless code from a meaningful one).

- **review-orchestration-guard** (`smith-ctx-claude/scripts/review-orchestration-guard.mjs`)
  — PreToolUse guard (matcher `Agent|Task`) that emits an **advisory** when a
  subagent is spawned whose `subagent_type` starts with an orchestrated-toolkit
  prefix (default `pr-review-toolkit:`, in
  `smith-ctx-claude/review-orchestration-config.json`): invoke the toolkit's
  orchestrator (`/review-pr`, or `/smith-review` which marshals it) so its full
  applicable agent set runs, instead of hand-picking individual agents. Advisory
  only (a one-off targeted spawn is legitimate).

- **skill-read-substitution-guard** (`smith-ctx-claude/scripts/skill-read-substitution-guard.mjs`)
  — PreToolUse guard (matcher `Read`) that emits an **advisory** when a
  `SKILL.md` under a skills root (markers in
  `smith-ctx-claude/skill-read-config.json`) is Read: to USE a skill, invoke it
  via the Skill tool (which loads and runs it); Read the `SKILL.md` directly only
  to quote or edit it. Advisory only.

- **skill-claim-lint** (`smith-ctx-claude/scripts/skill-claim-lint.mjs`) — Stop
  guard that streams the transcript and emits an **advisory** when the turn's
  message says `using @X` for a skill that was not actually invoked via the Skill
  tool that turn (mentioning or reading a skill is not using it). The read-time
  companion to `skill-read-substitution-guard`. Advisory only, never blocks.

- **gh-stack-guard** (`smith-ctx-claude/scripts/gh-stack-guard.mjs`)
  — PreToolUse guard (matcher `Bash`) that emits an **advisory** when a command
  hand-builds a stacked pull request (`gh pr create` with a non-default `--base`,
  or `git rebase --onto`) while the native `gh stack` extension (markers in
  `smith-ctx-claude/gh-stack-config.json`) is installed: prefer `gh stack`
  over the manual base-retarget and rebase cascade. Only fires when the extension
  is actually present (`gh extension list`); advisory only, never blocks.

- **rtk-find-symlink-guard** (`smith-ctx-claude/scripts/rtk-find-symlink-guard.mjs`,
  using shared helpers from `smith-ctx-claude/scripts/lib/git-command-tokenizer.mjs`)
  — PreToolUse guard (matcher `Bash`) that emits an **advisory** when a command
  invokes `find ... -L ...` or `rtk find ... -L ...`. Verified directly
  against the installed rtk 0.45.0: `rtk find` doesn't recognize `-L`, prints
  `rtk find: unknown flag '-L', ignored` to stderr, and exits 0 — but when
  `-L` precedes the search path (the idiomatic order, e.g. `-L . -type f`)
  it also drops that path and silently scans the current directory instead,
  so the result set isn't just missing a symlinked subtree, it can come from
  the wrong location entirely. Same known-unfixed bug class as
  github.com/rtk-ai/rtk#2821 — an unrecognized flag is warned on stderr, but
  the broader/wrong query still runs at exit 0; that report's own repro used
  `-newermt`, not `-L`, but it's the identical code path (verified open via
  `gh api repos/rtk-ai/rtk/issues/2821` on 2026-08-27; no open upstream issue
  names `-L` specifically, so this cites the matching bug class rather than
  implying `-L` itself was reported). Points to `test -f`
  for a plain existence check or `rtk proxy find ... -L ...` (per `RTK.md`,
  `rtk proxy <cmd>` executes the raw command "without filtering," i.e. real
  GNU/BSD find semantics, not rtk's own filtering) for unfiltered
  native-find output — `rtk proxy find` itself is correctly never flagged,
  since it already is the documented workaround. A `-L` that is itself the
  *value* of a preceding value-taking find predicate (`-name`, `-newer`,
  `-perm`, etc. — see `VALUE_TAKING_FIND_PREDICATES` in the script) is
  correctly NOT flagged — e.g. `find . -name "-L"` (searching for a file
  literally named `-L`) or `find . -newer -L` (comparing against a file
  named `L`) stay silent. Only fires when `rtk --help` lists a `gain`
  subcommand — `RTK.md` names `rtk gain` itself as the collision check
  ("If `rtk gain` fails, you may have reachingforthejack/rtk (Rust Type
  Kit) installed instead"), but actually RUNNING `rtk gain` as a presence
  probe has a real side effect: verified directly (`rtk gain` three times
  in a row) that it increments its own reported `Total commands` count on
  every invocation, so a probe run silently pollutes the user's own
  token-savings history. `--help` listing the documented `gain` subcommand
  is the same identity signal without that side effect (verified
  side-effect-free the same way) and without the `--version` output-shape
  ambiguity a same-shaped clap-based collision tool could also satisfy. A bare
  `find -L` is otherwise perfectly safe (real find). A bare `-L` occurring
  after `-exec`/`-execdir`/`-ok`/`-okdir` is not treated as the outer find's
  own flag, since it usually belongs to the wrapped sub-command — but that
  sub-command's own argument list (up to its `;`/`+` terminator) IS checked
  for being itself a `find`/`rtk find` invocation with its own `-L`, so
  `find . -exec rtk find -L {} \;` is still flagged (the sub-command's `-L`
  belongs to the nested `rtk find`, not the outer one, and the advisory's
  `'... ... -L'` wording names whichever invocation the `-L` actually sits
  on — the nested `rtk find`, not the outer bare `find`, which has no `-L`
  and would otherwise be blamed incorrectly). When a sub-command turns out
  NOT to be risky, the scan resumes past its terminator rather than
  abandoning the rest of the outer tokens, so a command with more than one
  `-exec`/`-execdir`/`-ok`/`-okdir` block still has every block checked —
  `find . -type f -exec true {} + -exec rtk find {} -L +` is flagged from
  the second block even though the first is benign. This is also true for
  a wrapped form like `find . -exec sudo rtk find -L {} +`, since the
  sub-command's own tokens are re-run through `unwrappedCommandSegments`
  (the same sudo/env/nohup/command unwrapping top-level segments get)
  rather than checked as raw tokens. Re-joining already-dequoted tokens
  with a plain space to do that re-run loses the original quote
  boundaries, so a quoted sub-command argument that happens to contain the
  literal substring `-L` as its own space-separated word (e.g. `-exec find
  -iname "report -L final.txt" {} \;`) can misfire as a false positive —
  accepted as a narrow, low-stakes trade-off of reusing the shared
  tokenizer rather than hand-rolling a second one, not attempted here. The
  sub-command's token span also ends at the first bare `;`/`+` token even
  when that token is itself one of the sub-command's own arguments rather
  than the real `-exec` terminator, which can under-warn if a genuinely
  risky nested invocation's `-L` sits after it — same narrow-edge-case
  trade-off, not attempted here. A `-L` placed on the OUTER find after a
  benign (non-risky) sub-command's terminator IS still caught, since the
  scan resumes from there rather than stopping at the first
  `-exec`/`-execdir`/`-ok`/`-okdir` block — verified: `find . -exec
  someprog {} + -L` is flagged.
  **Known limitation**: an explicit `rtk find -L` nested inside `xargs` (e.g.
  `xargs -I{} rtk find -L {} -type f`) or the shared tokenizer's own
  documented command-substitution limitation (see `external-write-guard`
  above) is not unwrapped, so it stays silent — the shared tokenizer has no
  xargs-unwrapping at all, and this would be a shared-lib enhancement
  benefiting every guard, not something to add ad hoc here. A deliberately
  obfuscated command name (`f\ind -L .`, which bash still resolves to and
  runs as `find`) also bypasses the cheap `FIND_HINT` pre-filter — this
  guard detects ordinary usage, not adversarial evasion, matching every
  other advisory-only guard in this file that inherits the shared
  tokenizer's own disclosed limitations rather than hardening against
  deliberate obfuscation; not attempted here. This does NOT
  extend to `gfind` (Homebrew findutils' binary name): verified directly via
  `rtk hook claude` that rtk's own transparent-rewrite hook rewrites bare
  `find` but leaves `gfind` untouched, so `gfind -L` runs real GNU find
  unaffected by rtk's `-L` handling — deliberately not flagged, and flagging
  it would be a false positive, not a fix. `-L` is one instance of a broader
  class rtk-ai/rtk#2821 documents (any unrecognized find flag gets the same
  warn-then-run-a-different-query treatment, e.g. `-newermt`) — this guard
  intentionally targets `-L` only; generalizing to arbitrary unrecognized
  flags is a natural follow-up, not attempted here. Advisory only, never
  blocks.

- **exit-plan-mode-guard** (`smith-ctx-claude/scripts/exit-plan-mode-guard.mjs`,
  using shared helpers from `smith-ctx-claude/scripts/lib/transcript-turns.mjs`)
  — PreToolUse guard (matcher `ExitPlanMode`) enforcing
  `smith-plan-claude/SKILL.md` §Explain Before ExitPlanMode: the plan
  explanation must be sent as its own turn (plain text, no tool call)
  before `ExitPlanMode` is called in a later, separate turn — never bundled
  into the same message, where the approval modal hides it. An earlier
  version of this guard also tried to read `last_assistant_message` to
  specifically detect that bundling, but per the official hooks docs
  (code.claude.com/docs/en/hooks) that field is populated only on
  `Stop`/`SubagentStop`, never `PreToolUse`, so that branch was silently
  dead code and has been removed.

  Claude Code writes one JSONL line per content block, not one line per
  logical turn — verified against live transcripts (18 sessions, 6,323
  assistant lines): text and `tool_use` never share a content array, only a
  `message.id`. A naive per-line scan for "an assistant message with both a
  substantial text block and a `tool_use` block" therefore never matches
  anything real (confirmed: 0 of 1,427 real mixed-content turns bundled
  both in one array), silently defeating the guard's whole purpose — this
  was caught and fixed before merge. `readTranscriptTurns` in the shared
  lib groups consecutive same-`message.id` lines into one logical turn
  first; only that grouped turn is checked for a `tool_use` block or
  summed for text length. Blocks unless scanning `transcript_path` finds a
  turn, since the last qualifying reset point, that is text-only (no
  `tool_use` block anywhere in the group) with at least 80 characters of
  combined text — text bundled into a turn that also contains a `tool_use`
  block (`ExitPlanMode` or otherwise) never qualifies, matching the actual
  transcript shape rather than an array that never occurs.

  The window resets to "not found" on: a genuine new top-level user
  message (real human input, not an `isMeta` system-reminder injection,
  not a `tool_result` continuation, via the shared `isGenuineNewUserTurn`
  helper — `skill-claim-lint.mjs` has its own inline version of this same
  check but does not import the helper and lacks the `isMeta` exclusion,
  so the two do not currently behave identically); or a prior `ExitPlanMode`
  tool-call attempt, so a rejected attempt always requires fresh
  elaboration before the retry rather than carrying the original stale
  elaboration through. The docs warn `transcript_path` "may not yet
  include the current turn's most recent messages when a hook fires," so
  the reset from an `ExitPlanMode` tool-call turn is applied differently
  depending on whether that same (grouped) turn ALSO carries at least 80
  characters of its own text: if so (substantial text bundled directly
  into the call), the reset applies immediately, blocking regardless of
  any earlier elaboration — this is the exact same-message-bundling
  threat, and it's visible in this turn's own content whether or not the
  transcript write lagged behind; if not (a clean call, or only trivial
  bundled text), the reset is deferred to the next turn, never applied to
  the turn that triggered it, so a clean call can never self-block just
  because its own line(s) happened to already be flushed. Both
  flush-timing cases, and both bundled-text sizes, are covered by
  dedicated tests. Sidechain (subagent) transcript events are skipped
  entirely — a subagent's own text-only response can never satisfy the
  main thread's elaboration requirement. Fails open on a missing/unreadable
  transcript or malformed hook input, distinguishing (stderr-only, never
  blocking either way) an expected missing-file case from an unexpected
  internal error, so a future logic bug is less likely to masquerade as
  intended fail-open silence. **Known limitations**: the 80-character
  floor and whole-window scan are a structural proxy for "was this
  explained," not a semantic one — a long but low-content message (e.g. a
  wall of pasted code) satisfies it, the threshold itself is untuned, and
  the scan does not check that the elaboration is topically about the plan
  actually being submitted (any qualifying prior turn's text since the
  last reset point counts). `skill-claim-lint.mjs` has the same
  turn-boundary duplication this guard used to have and has not been
  migrated to the shared lib — tracked as a follow-up, not attempted here
  (same "migrate later, don't retrofit silently" precedent as
  `branch-name-guard`'s Known Limitation above, which flags the analogous
  un-migrated duplication in `branch-rename-open-pr.mjs`/`gh-stack-guard.mjs`).
  `readTranscriptTurns`/`readTranscriptEvents` scan the transcript from the
  start on every `ExitPlanMode` call rather than backward from EOF —
  accepted as a low-priority inefficiency given how rarely `ExitPlanMode`
  fires per session, not attempted here.

- **stack-merge-guard** (`smith-ctx-claude/scripts/stack-merge-guard.mjs`,
  using shared helpers from `smith-ctx-claude/scripts/lib/git-command-tokenizer.mjs`)
  — PreToolUse guard (matcher `Bash`) that asks for confirmation on `gh pr merge
  --delete-branch` (or `-d`, including clustered short forms like `-sd`, and a
  boolean short flag clustered BEFORE a value-taking one like `-dt subject` —
  `gh`'s own short-flag clustering consumes everything after the first
  value-taking character as that flag's value, so `-d` is only a real,
  independent flag when it appears at or before that point; verified against
  the installed `gh` CLI, e.g. `-dt "text" <pr>` parses past flags. A cluster
  with `d` AFTER a value-taking char, like `-td`, is correctly NOT detected —
  the `d` there is consumed as `-t`'s value, not a separate flag) when
  another open PR has the branch being deleted as its base — deleting it leaves
  that child PR pointing at a deleted branch. Real incident this closes:
  `#86`->`#87` (2026-06-15). Resolves the PR's head branch via
  `gh pr view --json headRefName` (falling back to the current branch when no
  positional target is given) and searches for open children via `gh pr list
  --base <headRefName> --state open`. Falls back to `ask` (never silently
  allows) when either `gh` call errors or times out, or when a shell-wrapped command
  nests deeper than the shared tokenizer's unwrap limit, OR when an unexpected
  internal error occurs anywhere in the check itself — an unverified merge
  could just as easily be the dangerous case as the safe one, and an
  uncaught exception exits non-zero-but-not-2, which this repo's hooks treat
  as "does not block" rather than "ask," so leaving any part of the check
  outside a catch would silently defeat the guard on a future regression. A
  `-R`/`--repo` flag is recognized whether it appears BEFORE the `pr merge`
  subcommand (a global `gh` flag, e.g. `gh -R owner/repo pr merge ...` — the
  subcommand position itself is resolved by walking past recognized global
  flags rather than a naive first-match search, so a value that happens to
  read `pr`, e.g. `-R pr/pr`, can't be mistaken for the subcommand either) or
  AFTER it (a per-command flag, which takes precedence over a global one if
  both are present), and forwarded to the hook's own `gh pr view`/`gh pr list`
  verification calls either way, so cross-repo merges are checked against the
  actual target repo rather than the hook's own `cwd`. An explicit
  `--delete-branch=false`/`=0`/`=f`/`=F`/`=False`/`=FALSE` is recognized as
  the flag NOT being set, matching every spelling Go's `strconv.ParseBool`
  (which `gh`'s flag parser uses) accepts as false, verified against the
  installed `gh` CLI — so it does not trigger a spurious `ask` — and any
  `--delete-branch=<value>` token (any value, not just a negation) is removed
  from consideration before merge-target detection runs, so its split-off
  value can never be misread as the PR number/branch (e.g. `gh pr merge
  --delete-branch=true` with no other positional argument correctly falls
  back to the current branch's PR, not a literal `"true"` target). When
  `--delete-branch` appears more than once in any mix of forms (bare,
  `=value`, or clustered), the LAST occurrence decides the final state — a
  left-to-right scan, matching `gh`'s/pflag's own repeated-flag semantics —
  rather than always trusting whichever attached `=value` occurrence happens
  to appear first, verified against the installed `gh` CLI (a later flag
  overriding an earlier one is standard pflag/cobra behavior for a repeated
  flag). Suggests
  retargeting the child PR (`gh pr edit <number> --base <new-base>`) or using
  `gh stack` before merging. Value-taking short flags (`-A`/`-b`/`-F`/`-t`/`-R`)
  are recognized in space-separated, `--long=value`, attached short
  (`-Atext`), AND clustered form (e.g. `gh pr merge -dR owner/repo` splits
  into `-d` and `-R owner/repo`, so the repo is still correctly forwarded and
  `owner/repo` is never misread as the PR target — clustering is split at
  whichever character is the first value-taking one, matching the same
  left-to-right scan the delete-branch detector itself uses), verified against
  the installed `gh` CLI. Every `gh pr merge`/`gh pr view`/`gh pr list` call
  in the same hook invocation shares the PreToolUse 5-second subprocess
  timeout with no retry. Inherits the shared tokenizer's command-substitution
  limitation documented under `external-write-guard` above (`` gh $(echo pr)
  merge ``) — permanent, not tracked-fixable.

- **amend-shared-commit-guard** (`smith-ctx-claude/scripts/amend-shared-commit-guard.mjs`,
  using shared helpers from `smith-ctx-claude/scripts/lib/git-command-tokenizer.mjs`)
  — PreToolUse guard (matcher `Bash`) that asks for confirmation on `git commit
  --amend` when HEAD is also the tip of another local branch (`git branch
  --points-at HEAD`) — meaning the current branch has no commit of its own yet,
  so the commit being amended most likely belongs to a parent/base branch, not
  this one. This is the general, git-native form of the stacked-branch near-miss
  in `reference_amend_on_fresh_stacked_branch_rewrites_parent` (2026-08-17): a
  fresh child branch created off a parent's tip shares that tip until its first
  commit, so an early `--amend` silently rewrites the parent's history instead
  of creating the child's own commit. The same check also catches amending the
  very first commit on a fresh branch off the default branch, since HEAD then
  equals the default branch's tip too. A later `--no-amend` correctly
  overrides an earlier `--amend` (and vice versa) — git respects last-flag-wins
  for this pair, verified empirically (`git commit --amend --no-amend
  --allow-empty` creates a new commit, not an amend). Both flags are matched
  by any git-accepted unambiguous abbreviation (`--am`/`--amen`/`--amend`,
  `--no-am`/`--no-ame`/.../`--no-amend`), not just the full spelling — `--a`
  alone is genuinely ambiguous in git itself (errors with "could be
  --allow-empty or --allow-empty-message") and is correctly NOT treated as
  `--amend`; verified against the installed git CLI via `--dry-run`'s
  amend-specific restore hint. Detection scans forward, skipping the value of
  `git commit`'s own value-taking flags (`-m`/`-F`/`-C`/`-c`/`-A`/`--date`/
  `-t`/`--fixup`/`--squash`) — so a commit message that literally contains the
  text `--no-amend` is never misread as negating a real `--amend` elsewhere in
  the same command (verified: `git commit --amend -m "--no-amend"` still asks
  correctly), and the mirror case (a message reading `--amend` with no real
  amend flag present) correctly stays silent rather than firing a spurious
  ask. Falls back to `ask` (never silently allows)
  on an unverifiable `git rev-parse`/`git branch --points-at` call, an
  over-deep shell-wrapped command, or an unexpected internal error anywhere
  in the check itself, same rationale as `stack-merge-guard`.
  Skips detached `HEAD` (`git rev-parse --abbrev-ref HEAD` returns the literal
  string `HEAD`) since there is no branch to protect. **Known limitation**: a
  `git -C <other-repo> commit --amend` is evaluated against the hook's own
  `cwd`, not the command's `-C` target, matching `branch-rename-open-pr`'s
  existing precedent — not attempted here. Inherits the shared tokenizer's
  command-substitution limitation documented under `external-write-guard`
  above (`` X=$(git commit --amend) ``) — permanent, not tracked-fixable.

- **attribution-model-stamp** (`smith-ctx-claude/scripts/attribution-model-stamp.sh`)
  — PreToolUse hook (matcher `Bash`) for the deterministic `Assisted-by:`
  attribution mechanism. It is target-agnostic and **never inspects or rewrites the
  tool's arguments**: on each Bash call it reads the newest assistant
  `.message.model` from the session transcript and refreshes a cwd-keyed model file
  (`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans/.assisted-model-<cwd-hash>`), so the
  companion `attribution.sh` command has a fresh, correct model id. Keyed by working
  directory (git toplevel, else `pwd -P`) rather than by `session_key`, because
  `session_key` hashes `$PPID` and a Bash-tool subprocess cannot reproduce a hook's
  PPID — the working directory is the only coordinate both the hook and the command
  share. It picks up a mid-session `/model` switch from the next turn's Bash calls
  onward (the model id has no environment variable — `ANTHROPIC_MODEL` goes stale on
  switch; the switching turn's own commit can still read the prior model, since the
  new model's assistant line may not be flushed yet) and always exits 0 (fail-open);
  it emits no permission decision and never blocks a Bash call. Needs `jq`.

  `attribution.sh` (the single source of truth) reads that file and prints
  `Assisted-by: Claude:<model>` (or `Claude:<model>` with the `value` argument), or
  exits non-zero printing nothing if the model is unknown — so a trailer is omitted,
  never guessed. Every target **pulls** it, so the line is never hand-typed:
  - git commit → capture into an arg array so an unknown model omits the trailer
    rather than aborting the commit (a bare `git commit --trailer "$(…/attribution.sh)"`
    fails with `empty --trailer argument` when the model is unknown, and the
    `trailer.assisted-by.cmd` config form appends a dangling empty `Assisted-by:`):
    ```
    args=(-m "your message")
    ab=$(…/attribution.sh) && args+=(--trailer "$ab")
    git commit "${args[@]}"
    ```
    git parses the full `Assisted-by: Claude:<model>` line into a trailer.
  - gh PR body/comment → embed `$(…/attribution.sh)` in the body.
  - MCP writes (Slack/Jira/Confluence/Notion) → their arguments are not a shell, so
    the composer runs `attribution.sh` and includes its output when authoring the
    message. No MCP hook: the single source guarantees the format; only presence
    depends on remembering to include it.

  Limitations (by design; the model id is not reachable as an environment variable,
  so the file keyed by working directory is the only coordinate a hook and a
  Bash-context pull can share): two concurrent sessions in the SAME checkout on
  different models overwrite each other's `.assisted-model-<hash>` (worktrees are
  isolated by distinct git toplevel); the commit made in the same turn as a `/model`
  switch can still read the prior model; and each distinct repo leaves a small
  persistent `.assisted-model-<hash>` cache file under `plans/`.

Each ships a self-check under `smith-ctx-claude/scripts/tests/` (fixture JSON →
stdin, assert exit code + stdout); run them all with
`sh smith-ctx-claude/scripts/tests/run-all.sh`.

**Where to save it**: these are user-level hooks, so they belong in
`$HOME/.claude/settings.json` — not a project's `.claude/settings.json`.
Open (or create) it:

```shell
mkdir -p "$HOME/.claude" && ${EDITOR:-nano} "$HOME/.claude/settings.json"
```

- **No `settings.json` yet**: save the block below as-is — it's already a
  complete, valid file.
- **Already have one**: merge the `hooks` key in. If you already have
  entries under `hooks.UserPromptSubmit` or `hooks.PreToolUse`, append these
  hook objects to those arrays instead of replacing them — overwriting the
  array silently drops your existing hooks.

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/skill-router.mjs\"" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write|NotebookEdit|mcp__(plugin_serena_)?serena__(replace_content|replace_symbol_body|replace_in_files|insert_after_symbol|insert_before_symbol|safe_delete_symbol|rename_symbol|create_text_file)",
        "hooks": [
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/branch-guard.mjs\"" }
        ]
      },
      {
        "matcher": "EnterWorktree",
        "hooks": [
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/worktree-dirty-guard.mjs\"" }
        ]
      },
      {
        "matcher": "mcp__.*",
        "hooks": [
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/external-write-guard.mjs\"" }
        ]
      },
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/askuserquestion-arity.mjs\"" }
        ]
      },
      {
        "matcher": "ExitPlanMode",
        "hooks": [
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/exit-plan-mode-guard.mjs\"" }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/branch-rename-open-pr.mjs\"" },
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/branch-name-guard.mjs\"" },
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/gh-stack-guard.mjs\"" },
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/rtk-find-symlink-guard.mjs\"" },
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/stack-merge-guard.mjs\"" },
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/amend-shared-commit-guard.mjs\"" },
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/external-write-guard.mjs\"" },
          { "type": "command", "command": "bash \"$HOME/.claude/skills/smith-ctx-claude/scripts/attribution-model-stamp.sh\"" }
        ]
      },
      {
        "matcher": "Edit|Write|NotebookEdit",
        "hooks": [
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/comment-density-lint.mjs\"" },
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/coined-shorthand-lint.mjs\"" }
        ]
      },
      {
        "matcher": "Agent|Task",
        "hooks": [
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/review-orchestration-guard.mjs\"" }
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/skill-read-substitution-guard.mjs\"" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/volatile-artifact-guard.mjs\"" },
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/skill-claim-lint.mjs\"" }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/volatile-artifact-guard.mjs\"" }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "node \"$HOME/.claude/skills/smith-ctx-claude/scripts/volatile-artifact-guard.mjs\"" }
        ]
      }
    ]
  }
}
```

**Verify each hook actually fires** (a silent exit-0 looks like "passed" —
don't assume registration worked just because the JSON parses). Hook
definitions load at session start, so start a new `claude` session first,
then:

1. **skill-router** — send a prompt that matches a known trigger (e.g.
   mention "git commit"); confirm a skill-router advisory listing candidate
   skills appears.
2. **branch-guard** — on a repo's default branch, attempt an `Edit`/`Write`;
   confirm Claude Code blocks it citing branch-guard. Then create a
   branch/worktree and confirm the same edit proceeds normally.
3. **worktree-dirty-guard** — with uncommitted changes present, invoke
   `EnterWorktree`; confirm it's blocked citing the dirty checkout.
4. **external-write-guard** — trigger a human-facing MCP write (e.g. edit a
   Jira issue); confirm a permission prompt appears citing the external-write
   rule. If your settings already `allow` that MCP tool, the `ask` should
   still prompt per the "Resolved" note below; if it doesn't, that note's
   verified-from-docs claim doesn't hold on your install/version — report it.
   On the Bash channel: run `gh pr comment <n> --body "test"` and `gh pr
   review <n> --approve` against a scratch PR; confirm both prompt, then
   **deny** the prompt each time (a real comment/approval would otherwise post
   to the scratch PR). Confirm `gh pr view <n>` and `gh api graphql -f
   query='mutation { resolveReviewThread(input: {threadId: "PRRT_invalid"}) {
   thread { isResolved } } }'` do NOT prompt (the deliberately-invalid
   `threadId` makes the request itself fail harmlessly server-side — nothing
   real gets resolved — while still confirming the guard doesn't intercept
   it).
5. **askuserquestion-arity** — send a 2-question `AskUserQuestion`; confirm it
   is blocked. A single question proceeds.
6. **volatile-artifact-guard** — write a file under `/tmp`, then stop; confirm
   the advisory lists it.
7. **branch-rename-open-pr** — on a branch with an open PR, attempt
   `git branch -m`; confirm it is blocked.
8. **branch-name-guard** — attempt `git checkout -b feat/bad_name`; confirm
   it is blocked with a suggested fix (`feat/bad-name`). Attempt
   `git checkout -b wip/no-type-prefix`; confirm it is blocked (no
   suggestion offered — `wip` isn't a fixable typo of a known type). Then
   `git checkout -b feat/good-name`; confirm it proceeds.
9. **comment-density-lint** — write a code file whose new content is heavy on
   inline comments; confirm the advisory reminder appears (the write still
   proceeds).
10. **coined-shorthand-lint** — write a file introducing two or more `[A-Z][0-9]`
    labels (e.g. `T1`, `T2`); confirm the advisory appears.
11. **review-orchestration-guard** — spawn a `pr-review-toolkit:*` subagent;
    confirm the advisory points you to `/review-pr` / `/smith-review`.
12. **skill-read-substitution-guard** — Read a `SKILL.md` under a skills root;
    confirm the advisory points you to the Skill tool.
13. **skill-claim-lint** — end a turn whose message says `using @some-skill`
    without invoking it via the Skill tool; confirm the advisory appears.
14. **gh-stack-guard** — with the `gh stack` extension installed,
    run `gh pr create --base <a-non-default-branch>`; confirm the advisory points
    you to `gh stack`. Without the extension it stays silent.
15. **attribution-model-stamp** — run any Bash command, then confirm
    `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plans/.assisted-model-*` holds the current
    model id, and that `smith-ctx-claude/scripts/attribution.sh` prints
    `Assisted-by: Claude:<model>`. The Bash call is never blocked or altered.
16. **exit-plan-mode-guard** — in plan mode, call `ExitPlanMode` in the same
    message as the plan explanation (or with no prior elaboration turn at
    all); confirm it is blocked. Then send the explanation as its own
    plain-text turn first, and call `ExitPlanMode` with no accompanying
    text in a later turn; confirm it proceeds. If the call is rejected with
    feedback, confirm a bare retry (no fresh elaboration turn) is blocked,
    and that sending fresh elaboration before the retry proceeds.
17. **stack-merge-guard** — with an open PR whose base is a branch that has
    its own open PR, run `gh pr merge <the-base-PR> --delete-branch`; confirm
    it prompts naming the still-open child PR, then **deny** the prompt (a
    real merge would otherwise delete the base branch out from under the
    child). Confirm `gh pr merge <either-PR>` without `--delete-branch` does
    NOT prompt.
18. **amend-shared-commit-guard** — create a branch off another branch's tip
    with no commit of your own yet (`git switch -c scratch/probe`), then run
    `git commit --amend`; confirm it prompts naming the other branch, then
    **deny** the prompt (a real amend would otherwise rewrite the parent
    branch's commit). Make a real commit on `scratch/probe`, then run
    `git commit --amend --no-edit`; confirm it proceeds without prompting.
19. **rtk-find-symlink-guard** — with rtk installed, run `find -L . -type f`
    (or `rtk find -L . -type f`); confirm the advisory appears pointing to
    `test -f` / `rtk proxy find`. Confirm `rtk proxy find -L . -type f` and a
    plain `find . -type f` (no `-L`) stay silent.

**Note on `ask` vs another matching hook's decision.** Verified against the
raw current text of code.claude.com/docs/en/hooks (fetched directly, not
through a summarizing pass — an earlier summarized fetch fabricated a
"most restrictive: deny beats allow, both beat ask" claim that does not
appear anywhere on the page): "When multiple `PreToolUse` hooks return
different decisions, precedence is `deny > defer > ask > allow`." So a
plain `"allow"` from another hook matching the same tool call cannot
silently downgrade this guard's `"ask"`. A CodeRabbit finding on PR #170
claimed the opposite (another matching `PreToolUse` hook "can override or
drop this hook's permission decision, allowing the external write without
prompting") — checked against this verified precedence and found
inapplicable; no code or doc change made for that specific claim (same
checked-and-rejected precedent as the `isMeta` finding on PR #183).

**Resolved: a pre-existing `permissions.allow` grant does not skip this
guard.** Verified against the same raw doc fetch as above: "PreToolUse hooks
run before every tool call, whether or not it needs permission" — so a
standing `allow` for a matched tool in `$HOME/.claude/settings.json` cannot
cause the hook to be skipped; it still runs and its `"ask"` still applies.
Separately: "A hook's `\"ask\"` also forces a permission prompt in auto mode:
the classifier can still deny the tool call, but it can't approve the call
silently. Before v2.1.211, the classifier could approve a Bash command
running outside the sandbox without showing the prompt the hook requested
[...]; a hook `\"deny\"` was always honored" — that narrower pre-v2.1.211
exception is fixed upstream (this machine runs 2.1.245). Manually confirm
(step 4 above) on your own install/version regardless, since this is
verified from docs, not from an empirical test on a standing `allow` rule.
Separately, unrelated to `permissions.allow`: a `PermissionRequest` hook can
resolve a permission prompt "on behalf of the user" (confirmed in the docs)
— a different, real bypass vector from the multi-`PreToolUse`-hook claim
above, but no `PermissionRequest` hook is currently registered anywhere in
this repo or in any of this machine's Claude Code profiles, so there is
nothing to defend against yet; noted here rather than speculatively guarded
against.

### Checkpoint & reload prerequisites

`/smith-checkpoint` (capture) and its post-`/clear` reload flag have runtime
dependencies. If they are missing, capture may still be attempted but the
checkpoint is **incomplete** — it is not successful until all three backend
writes succeed (the skill reports which failed rather than claiming success),
and reload degrades:

- **MCP servers** — the lifecycle writes and reads through them: **Serena**
  (`write_memory`/`read_memory`), **Basic-Memory** (`write_note` / note search).
  Both are **local-only** in a default setup (Serena memories live under
  `.serena/memories`, typically gitignored; Basic-Memory is a local SQLite DB
  unless Basic-Memory Cloud is enabled). auto-memory lives under
  `~/.claude/projects/«project»/memory/` (Claude Code, local).
- **Reload-flag hook** — the memory-restore directive is injected as context on
  the next `/clear` only if the `smith-plan-claude` **SessionStart:clear** hook
  (`on-session-clear.sh`) is registered; the restore itself executes at the
  user's first prompt after `/clear` (any prompt) — hooks cannot start a model
  turn in an interactive session. That hook set (SessionStart / Stop /
  UserPromptSubmit / PostToolUse) is documented in
  `smith-plan-claude/references/HOOKS.md`; without it, use the manual
  `/smith-recon "resume …"` path printed in the checkpoint's Reload block.
- **Cloud / fresh-clone reach** — a cloud run (`/schedule`, `/code-review ultra`,
  Claude Code web) clones the repo fresh with no local home dir, so it sees
  **none** of the local backends — only committed git/PR state. Portable resume
  there needs committed-to-repo state or an enabled cloud MCP (deferred).

## Structure

```text
smith/
├── AGENTS.md              # Main entry point (agents.md standard)
├── smith-{skill-name}/
│   └── SKILL.md           # Skill file (agentskills.io standard)
└── ...
```

### Skills (47 total)

| Category | Skills |
|----------|--------|
| **Core** | `smith-principles`, `smith-standards`, `smith-guidance` |
| **Commands** (`/smith-X`) | `smith-ship`, `smith-review`, `smith-preflight`, `smith-checkpoint`, `smith-recon`, `smith-tickets` |
| **Context** | `smith-ctx`, `smith-ctx-claude`, `smith-ctx-kiro`, `smith-ctx-cursor`, `smith-serena` |
| **Reasoning** | `smith-analysis`, `smith-clarity`, `smith-design`, `smith-validation`, `smith-postmortem`, `smith-dialectic` |
| **Languages** | `smith-python`, `smith-typescript`, `smith-nuxt` |
| **Testing** | `smith-tests`, `smith-playwright`, `smith-browser_mcp` |
| **Workflow** | `smith-ralph`, `smith-plan`, `smith-plan-claude`, `smith-subagents`, `smith-automation` |
| **Git/GitHub** | `smith-git`, `smith-gh-pr`, `smith-gh-cli`, `smith-style`, `smith-worktree` |
| **Communication** | `smith-slack` |
| **Other** | `smith-prompts`, `smith-xml`, `smith-placeholder`, `smith-tools`, `smith-dev`, `smith-ide`, `smith-research`, `smith-skills`, `smith-settings`, `smith-auto_mode` |

### SKILL.md Format

Each skill follows [agentskills.io specification](https://agentskills.io/specification)[[29]](#ref-29).
Bodies use plain Markdown (headers, bold labels, bullet lists) — not an XML
tag skeleton — matching Anthropic's own SKILL.md-authoring examples and
OpenAI's current model guidance; see `smith-xml/SKILL.md` for the narrower
case where XML tags still apply (runtime prompts, not SKILL.md bodies):

```yaml
---
name: skill-name        # Must match directory name
description: ...        # When to use this skill
---

# Skill Title

**Load if:** Conditions for activation
**Prerequisites:** Dependencies

## Section Title

Instructions...

## Related

- `@other/SKILL.md` - Description
```

### Reference Convention

- `@path/SKILL.md` (bare) — Always-loaded skills
- `` `@path/SKILL.md` `` (backticks) — Contextual/on-demand skills

## Platform Compatibility

See [AGENTS.md](AGENTS.md) for the full skill index and loading protocol. Global AGENTS.md support is an ongoing discussion[[27]](#ref-27).

### Native AGENTS.md Support

| Tool | Global Config | Project Config |
|------|---------------|----------------|
| **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)**[[4]](#ref-4) | `~/.claude/CLAUDE.md` | `AGENTS.md` |
| **[OpenAI Codex](https://developers.openai.com/codex/guides/agents-md/)**[[16]](#ref-16) | `~/.codex/AGENTS.md` | `AGENTS.md` |
| **[Amp](https://ampcode.com/manual)**[[2]](#ref-2) | `~/.config/AGENTS.md`[[26]](#ref-26) | `AGENTS.md` |
| **[Devin](https://devin.ai/)**[[8]](#ref-8) | — | `AGENTS.md` |
| **[Kiro](https://kiro.dev/docs/steering/)**[[15]](#ref-15) | `~/.kiro/steering/` | `AGENTS.md` |
| **[VS Code](https://code.visualstudio.com/updates/v1_104)**[[21]](#ref-21) | — | `AGENTS.md` |
| **[Windsurf](https://docs.windsurf.com/)**[[23]](#ref-23) | `.windsurf/rules` | `AGENTS.md` |
| **[Zed](https://zed.dev/docs/ai/agent-panel)**[[24]](#ref-24) | —[[25]](#ref-25) | `AGENTS.md` |
| **[goose](https://github.com/block/goose)**[[12]](#ref-12) | — | `AGENTS.md` |

### Requires Configuration

| Tool | Global Config | Project Config |
|------|---------------|----------------|
| **[Aider](https://aider.chat/)**[[1]](#ref-1) | `~/.aider.conf.yml` | `AGENTS.md` |
| **[Gemini CLI](https://developers.google.com/gemini-code-assist/docs/use-agentic-chat-pair-programmer)**[[9]](#ref-9) | `~/.gemini/` | `GEMINI.md` |
| **[GitHub Copilot](https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot)**[[10]](#ref-10) | —[[11]](#ref-11) | `.github/copilot-instructions.md` |
| **[JetBrains AI](https://www.jetbrains.com/help/ai-assistant/configure-project-rules.html)**[[13]](#ref-13) | `~/.config/JetBrains/*/ai-assistant/rules/` | `.aiassistant/rules/` |
| **[Continue](https://docs.continue.dev/)**[[5]](#ref-5) | `~/.continue/config.yaml` | `.continue/` |

### Different Format

| Tool | Format | Project Config |
|------|--------|----------------|
| **[Cursor](https://docs.cursor.com/context/rules)**[[6]](#ref-6)[[7]](#ref-7) | `.mdc` | `.cursor/rules/*.mdc` |
| **[Antigravity](https://cloud.google.com/products/antigravity)**[[3]](#ref-3) | `GEMINI.md` | `.agent/rules/` |

<details>
<summary>All supported tools</summary>

- **[JetBrains Junie](https://www.jetbrains.com/help/junie/customize-guidelines.html)**[[14]](#ref-14): `.junie/guidelines.md`
- **[OpenHands](https://docs.openhands.dev/)**[[17]](#ref-17): `.openhands/microagents/`
- **[Roo Code](https://docs.roocode.com/features/custom-instructions)**[[18]](#ref-18): `.roo/rules/`
- **[Sourcegraph Cody](https://sourcegraph.com/docs/cody)**[[19]](#ref-19): Enterprise only
- **[Tabnine](https://docs.tabnine.com/main/getting-started/tabnine-agent/guidelines)**[[20]](#ref-20): `.tabnine/guidelines/`
- **[Warp](https://docs.warp.dev/agents/using-agents)**[[22]](#ref-22): `WARP.md`

</details>

## References

1. <span id="ref-1"></span>[Aider](https://aider.chat/)
2. <span id="ref-2"></span>[Amp Manual](https://ampcode.com/manual)
3. <span id="ref-3"></span>[Antigravity Rules](https://atamel.dev/posts/2025/11-25_customize_antigravity_rules_workflows/)
4. <span id="ref-4"></span>[Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
5. <span id="ref-5"></span>[Continue](https://docs.continue.dev/)
6. <span id="ref-6"></span>[Cursor Rules](https://docs.cursor.com/context/rules)
7. <span id="ref-7"></span>[Cursor Global Config Request](https://forum.cursor.com/t/support-for-cursor-rules-for-global-mdc-rules/144819)
8. <span id="ref-8"></span>[Devin by Cognition](https://devin.ai/)
9. <span id="ref-9"></span>[Gemini CLI / Code Assist](https://developers.google.com/gemini-code-assist/docs/use-agentic-chat-pair-programmer)
10. <span id="ref-10"></span>[GitHub Copilot Custom Instructions](https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot)
11. <span id="ref-11"></span>[GitHub Copilot JetBrains Global Config](https://devblogs.microsoft.com/java/customize-github-copilot-in-jetbrains-with-custom-instructions/)
12. <span id="ref-12"></span>[goose by Block](https://github.com/block/goose)
13. <span id="ref-13"></span>[JetBrains AI Assistant Rules](https://www.jetbrains.com/help/ai-assistant/configure-project-rules.html)
14. <span id="ref-14"></span>[JetBrains Junie Guidelines](https://www.jetbrains.com/help/junie/customize-guidelines.html)
15. <span id="ref-15"></span>[Kiro Steering](https://kiro.dev/docs/steering/)
16. <span id="ref-16"></span>[OpenAI Codex AGENTS.md Guide](https://developers.openai.com/codex/guides/agents-md/)
17. <span id="ref-17"></span>[OpenHands Microagents](https://docs.openhands.dev/modules/usage/prompting/microagents-repo)
18. <span id="ref-18"></span>[Roo Code Custom Instructions](https://docs.roocode.com/features/custom-instructions)
19. <span id="ref-19"></span>[Sourcegraph Cody](https://sourcegraph.com/docs/cody)
20. <span id="ref-20"></span>[Tabnine Guidelines](https://docs.tabnine.com/main/getting-started/tabnine-agent/guidelines)
21. <span id="ref-21"></span>[VS Code AGENTS.md Support](https://code.visualstudio.com/updates/v1_104)
22. <span id="ref-22"></span>[Warp Agents](https://docs.warp.dev/agents/using-agents)
23. <span id="ref-23"></span>[Windsurf Documentation](https://docs.windsurf.com/)
24. <span id="ref-24"></span>[Zed Agent Panel](https://zed.dev/docs/ai/agent-panel)
25. <span id="ref-25"></span>[Zed Global Config Discussion](https://github.com/zed-industries/zed/discussions/36560)
26. <span id="ref-26"></span>[XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/)
27. <span id="ref-27"></span>[Global AGENTS.md Proposal](https://github.com/openai/agents.md/issues/91)
28. <span id="ref-28"></span>[AGENTS.md Standard](https://agents.md)
29. <span id="ref-29"></span>[Agent Skills Specification](https://agentskills.io)

## License

MIT
