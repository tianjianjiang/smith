#!/bin/sh
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../external-write-guard.mjs"

fail() { echo "FAIL: $1"; exit 1; }
run() { printf '%s' "$1" | node "$HOOK"; }
asks() { run "$2" | grep -q '"permissionDecision":"ask"' || fail "$1: expected ask"; }
silent() {
  out=$(run "$2") || fail "$1: hook crashed"
  [ -z "$out" ] || fail "$1: expected silent, got: $out"
}

asks   "editJiraIssue"        '{"tool_name":"mcp__plugin_atlassian_atlassian__editJiraIssue","tool_input":{}}'
asks   "addCommentToJira"     '{"tool_name":"mcp__plugin_atlassian_atlassian__addCommentToJiraIssue","tool_input":{}}'
asks   "notion-create-pages"  '{"tool_name":"mcp__plugin_Notion_notion__notion-create-pages","tool_input":{}}'
asks   "notion-update-page"   '{"tool_name":"mcp__plugin_Notion_notion__notion-update-page","tool_input":{}}'
asks   "notion-move-pages"    '{"tool_name":"mcp__plugin_Notion_notion__notion-move-pages","tool_input":{}}'
asks   "notion-duplicate"     '{"tool_name":"mcp__plugin_Notion_notion__notion-duplicate-page","tool_input":{}}'
asks   "confluence create"    '{"tool_name":"mcp__plugin_atlassian_atlassian__createConfluencePage","tool_input":{}}'
asks   "confluence update"    '{"tool_name":"mcp__plugin_atlassian_atlassian__updateConfluencePage","tool_input":{}}'
asks   "slack non-draft send" '{"tool_name":"mcp__plugin_slack_slack__slack_send_message","tool_input":{}}'
asks   "slack schedule send"  '{"tool_name":"mcp__plugin_slack_slack__slack_schedule_message","tool_input":{}}'

silent "slack draft variant"  '{"tool_name":"mcp__plugin_slack_slack__slack_send_message_draft","tool_input":{}}'
silent "getJiraIssue read"    '{"tool_name":"mcp__plugin_atlassian_atlassian__getJiraIssue","tool_input":{}}'
silent "notion-fetch read"    '{"tool_name":"mcp__plugin_Notion_notion__notion-fetch","tool_input":{}}'
silent "unrelated tool"       '{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
silent "malformed stdin"      'not json at all'

echo "PASS: external-write-guard"
