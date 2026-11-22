ISOLATED_WORKER_DENIED_TOOLS="Agent Edit Write NotebookEdit WebFetch WebSearch"

require_live_probe_opt_in() {
  if [ "${SMITH_LIVE_CONTEXT_RESET_EVAL:-}" != "1" ]; then
    echo "SKIP: set SMITH_LIVE_CONTEXT_RESET_EVAL=1 to run this live probe"
    exit 0
  fi
  command -v claude > /dev/null || { echo "SKIP: claude is not on PATH"; exit 0; }
}

build_isolated_worker_argv() {
  local model="$1" allowed="$2" denied="$3" output_format="$4" prompt="$5"
  shift 5
  ISOLATED_WORKER_ARGV=(env -u CLAUDE_JOB_DIR CTX_AUTO_RESET_DISPATCH=0 claude -p
    --strict-mcp-config
    --no-session-persistence
    --output-format "$output_format"
    --model "$model"
    --disallowedTools "$ISOLATED_WORKER_DENIED_TOOLS $denied"
    "$@")
  if [ -n "$allowed" ]; then
    ISOLATED_WORKER_ARGV+=(--allowedTools "$allowed")
  fi
  ISOLATED_WORKER_ARGV+=(-- "$prompt")
}

is_live_pid() {
  case "${1:-}" in '' | 0 | *[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2> /dev/null
}

stream_parse_error_variant() {
  jq -n --arg name "$1" --argjson status "$2" '{variant: $name, exitStatus: $status, streamParseError: true, pass: false}'
}

probe_timestamp() {
  date +%Y-%m-%dT%H:%M:%S%z | sed -E 's/([0-9]{2})([0-9]{2})$/\1:\2/'
}

profile_label() {
  local dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  printf '%s' "~${dir#"$HOME"}"
}
