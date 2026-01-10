#!/bin/bash
# Claude Code Status Line with Real-time Usage Limits
# Shows: Model | Context % | Session (5hr) % | Week (7day) % | Directory
#
# Features:
# - Real-time subscription usage from Anthropic API
# - Color-coded warnings (green/yellow/red based on usage %)
# - 60-second cache to minimize API calls
#
# Requirements: jq, curl, macOS (uses Keychain for OAuth token)
#
# Installation:
#   1. Save this file to ~/.claude/statusline-command.sh
#   2. chmod +x ~/.claude/statusline-command.sh
#   3. Add to ~/.claude/settings.json:
#      { "statusLine": { "type": "command", "command": "~/.claude/statusline-command.sh" } }

# ANSI color codes
RED='\033[31m'
YELLOW='\033[33m'
GREEN='\033[32m'
CYAN='\033[36m'
DIM='\033[2m'
RESET='\033[0m'

# Read JSON input from stdin (provided by Claude Code)
input=$(cat)

# === Fetch Usage from Anthropic API (with 60s cache) ===
CACHE_FILE="$HOME/.claude/usage-cache.json"
CACHE_MAX_AGE=60

fetch_usage() {
    local token
    token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken' 2>/dev/null)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        curl -s "https://api.anthropic.com/api/oauth/usage" \
            -H "Authorization: Bearer $token" \
            -H "User-Agent: claude-code/2.0.32" \
            -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null
    fi
}

# Check cache
usage_json=""
if [ -f "$CACHE_FILE" ]; then
    cache_age=$(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)))
    if [ "$cache_age" -lt "$CACHE_MAX_AGE" ]; then
        usage_json=$(cat "$CACHE_FILE")
    fi
fi

# Fetch if cache is stale
if [ -z "$usage_json" ] || [ "$usage_json" = "null" ]; then
    usage_json=$(fetch_usage)
    if [ -n "$usage_json" ] && [ "$usage_json" != "null" ]; then
        echo "$usage_json" > "$CACHE_FILE"
    fi
fi

# Parse usage percentages (5-hour session, 7-day week)
five_hour_pct=$(echo "$usage_json" | jq -r '.five_hour.utilization // 0' 2>/dev/null)
seven_day_pct=$(echo "$usage_json" | jq -r '.seven_day.utilization // 0' 2>/dev/null)
[ "$five_hour_pct" = "null" ] && five_hour_pct=0
[ "$seven_day_pct" = "null" ] && seven_day_pct=0

# === Parse Status Line JSON ===
model_name=$(echo "$input" | jq -r '.model.display_name')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
usage=$(echo "$input" | jq '.context_window.current_usage')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size')

# Calculate context percentage
context_pct=0
if [ "$usage" != "null" ]; then
    input_tokens=$(echo "$usage" | jq -r '.input_tokens // 0')
    cache_creation=$(echo "$usage" | jq -r '.cache_creation_input_tokens // 0')
    cache_read=$(echo "$usage" | jq -r '.cache_read_input_tokens // 0')
    current_context=$((input_tokens + cache_creation + cache_read))

    if [ "$context_size" != "null" ] && [ "$context_size" -gt 0 ]; then
        context_pct=$((current_context * 100 / context_size))
    fi
fi

dir_name=$(basename "$cwd")

# === Color Selection (green < 50% < yellow < 80% < red) ===
select_color() {
    local pct=$1
    if [ "$pct" -ge 80 ]; then
        echo "$RED"
    elif [ "$pct" -ge 50 ]; then
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}

ctx_color=$(select_color "$context_pct")
session_color=$(select_color "$five_hour_pct")
week_color=$(select_color "$seven_day_pct")

# === Output ===
printf "${CYAN}%s${RESET} ${DIM}|${RESET} Ctx: ${ctx_color}%d%%${RESET} ${DIM}|${RESET} Session: ${session_color}%d%%${RESET} ${DIM}|${RESET} Week: ${week_color}%d%%${RESET} ${DIM}|${RESET} ${DIM}%s${RESET}" \
    "$model_name" \
    "$context_pct" \
    "$five_hour_pct" \
    "$seven_day_pct" \
    "$dir_name"
