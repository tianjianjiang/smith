Add a checker for the PR body template, so that a body missing a part
fails a test instead of a review.

**How to revert**: revert the squash commit; no other change depends on it.

Testing: ran smith-gh-pr/scripts/tests/run-all.sh and skill-lint locally; no CI check backs it.

Assisted-by: Claude:claude-opus-5-5
