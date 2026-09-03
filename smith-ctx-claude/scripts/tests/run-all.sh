#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
status=0
for check in \
  context-warning \
  checkpoint-label \
  external-write-guard \
  askuserquestion-arity \
  volatile-artifact-guard \
  branch-rename-open-pr \
  coined-shorthand-lint \
  review-orchestration-guard \
  skill-read-substitution-guard \
  skill-claim-lint \
  gh-stack-guard \
  attribution \
  git-command-tokenizer \
  transcript-turns \
  exit-plan-mode-guard \
  amend-shared-commit-guard \
  stack-merge-guard \
  rtk-find-symlink-guard \
  subagent-contract-guard \
  spawn-ledger-report \
  post-merge-pull-reminder
do
  sh "$HERE/$check.test.sh" || status=1
done
[ "$status" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$status"
