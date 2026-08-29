#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
status=0
for check in \
  external-write-guard \
  askuserquestion-arity \
  volatile-artifact-guard \
  branch-rename-open-pr \
  comment-density-lint \
  coined-shorthand-lint \
  review-orchestration-guard \
  skill-read-substitution-guard \
  skill-claim-lint \
  gh-stack-guard \
  attribution \
  branch-name-guard \
  git-command-tokenizer \
  transcript-turns \
  exit-plan-mode-guard \
  amend-shared-commit-guard \
  stack-merge-guard \
  rtk-find-symlink-guard \
  post-merge-pull-reminder
do
  sh "$HERE/$check.test.sh" || status=1
done
[ "$status" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$status"
