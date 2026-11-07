#!/bin/sh
set -eu
dir="${CLAUDE_JOB_DIR:-${TMPDIR:-/tmp}}"
mktemp "${dir%/}/checkpoint-body.XXXXXX"
