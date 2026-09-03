#!/bin/bash
#
# uv-tool-health-check.sh - SessionStart hook, self-heals a broken uv-tool venv
#
# `uv tool install` links a persistent venv to a specific Python interpreter
# at install time; if that interpreter is later upgraded or removed (a
# MacPorts point-upgrade, a pruned uv-managed Python build, etc.), the venv's
# bin/python3 symlink breaks and every entrypoint fails with "bad interpreter"
# -- verified 2026-08-27 (serena-hooks failed this way on every Read) and
# confirmed as an acknowledged, closed-as-not-planned uv limitation:
# github.com/astral-sh/uv/issues/8514, /7634, /7651, /8028. uv itself will
# not fix this -- a proposed "uv tool reinstall-all" was rejected as a
# duplicate -- so recovery is this repo's own responsibility.
#
# Scope is deliberately narrow: only the tools this repo actually depends on
# functioning, not every uv tool on the machine. Broadening MONITORED_TOOLS
# is a reviewed change, not something this hook should decide unilaterally.
MONITORED_TOOLS=(serena-agent)

command -v uv >/dev/null 2>&1 || exit 0

_uhc_stderr=$(uv tool list 2>&1 >/dev/null)
_uhc_healed=()
_uhc_failed=()

for _uhc_tool in "${MONITORED_TOOLS[@]}"; do
    echo "$_uhc_stderr" | grep -q "tools/${_uhc_tool}/bin/python3" || continue
    if uv tool install "$_uhc_tool" --reinstall >/dev/null 2>&1; then
        _uhc_healed+=("$_uhc_tool")
    else
        _uhc_failed+=("$_uhc_tool")
    fi
done

if [[ ${#_uhc_healed[@]} -eq 0 && ${#_uhc_failed[@]} -eq 0 ]]; then
    exit 0
fi

_uhc_msg=""
if [[ ${#_uhc_healed[@]} -gt 0 ]]; then
    _uhc_msg="uv-tool-health-check: reinstalled broken tool venv(s): ${_uhc_healed[*]} (their bin/python3 symlink pointed at a removed Python interpreter)."
fi
if [[ ${#_uhc_failed[@]} -gt 0 ]]; then
    _uhc_msg="${_uhc_msg} FAILED to reinstall: ${_uhc_failed[*]} -- run \`uv tool install <name> --reinstall\` manually."
fi

command -v jq >/dev/null 2>&1 || { echo "$_uhc_msg" >&2; exit 0; }

jq -n --arg msg "$_uhc_msg" '{
    hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: $msg
    },
    systemMessage: $msg
}'
