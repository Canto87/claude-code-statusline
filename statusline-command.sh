#!/bin/bash

# ANSI color codes
RED='\033[31m'
YELLOW='\033[33m'
GREEN='\033[32m'
CYAN='\033[36m'
DIM='\033[2m'
RESET='\033[0m'

# Read JSON input from stdin
input=$(cat)

# Fetch usage from API (with 60s cache)
CACHE_FILE="$HOME/.claude/usage-cache.json"
CACHE_MAX_AGE=60

fetch_usage() {
    local token
    token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken' 2>/dev/null)
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        # Use temp config file to avoid exposing token in process list
        local config_file=$(mktemp)
        chmod 600 "$config_file"
        cat > "$config_file" << EOF
-s
-H "Authorization: Bearer $token"
-H "User-Agent: claude-code/2.0.32"
-H "anthropic-beta: oauth-2025-04-20"
EOF
        curl -K "$config_file" "https://api.anthropic.com/api/oauth/usage" 2>/dev/null
        rm -f "$config_file"
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
        # Secure cache file permissions (owner read/write only)
        (umask 077 && echo "$usage_json" > "$CACHE_FILE")
    fi
fi

# Parse usage percentages and reset times
five_hour_pct=$(echo "$usage_json" | jq -r '.five_hour.utilization // 0' 2>/dev/null)
five_hour_reset=$(echo "$usage_json" | jq -r '.five_hour.resets_at // ""' 2>/dev/null)
seven_day_pct=$(echo "$usage_json" | jq -r '.seven_day.utilization // 0' 2>/dev/null)
seven_day_reset=$(echo "$usage_json" | jq -r '.seven_day.resets_at // ""' 2>/dev/null)
seven_day_sonnet_pct=$(echo "$usage_json" | jq -r '.seven_day_sonnet.utilization // 0' 2>/dev/null)

[ "$five_hour_pct" = "null" ] && five_hour_pct=0
[ "$seven_day_pct" = "null" ] && seven_day_pct=0
[ "$seven_day_sonnet_pct" = "null" ] && seven_day_sonnet_pct=0

# Format reset times to local timezone
format_reset_time() {
    local iso_time="$1"
    local format="$2"
    if [ -n "$iso_time" ] && [ "$iso_time" != "null" ] && [ "$iso_time" != "" ]; then
        # Convert ISO 8601 to Unix timestamp, then to local time
        # Remove timezone suffix and milliseconds for parsing
        local clean_time=$(echo "$iso_time" | sed 's/\.[0-9]*//; s/+00:00$/Z/; s/Z$//')
        local unix_ts=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$clean_time" "+%s" 2>/dev/null)
        if [ -n "$unix_ts" ]; then
            LC_ALL=C date -r "$unix_ts" "$format" 2>/dev/null
        fi
    fi
}

# Session: "11:00pm", Week: "Jan17 5:59pm"
session_reset_display=$(format_reset_time "$five_hour_reset" "+%-I:%M%p" | sed 's/AM/am/; s/PM/pm/')
week_reset_display=$(format_reset_time "$seven_day_reset" "+%b%d %-I:%M%p" | sed 's/AM/am/; s/PM/pm/')

# Extract data using jq
model_id=$(echo "$input" | jq -r '.model.id')
model_name=$(echo "$input" | jq -r '.model.display_name')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
usage=$(echo "$input" | jq '.context_window.current_usage')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size')
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens')

# Session cost from cost object
session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

# Initialize display variables
context_pct="0"
tokens_display="--"
cost_display="\$0.00"

# Calculate context percentage and cost if usage data exists
if [ "$usage" != "null" ]; then
    input_tokens=$(echo "$usage" | jq -r '.input_tokens')
    output_tokens=$(echo "$usage" | jq -r '.output_tokens')
    cache_creation=$(echo "$usage" | jq -r '.cache_creation_input_tokens')
    cache_read=$(echo "$usage" | jq -r '.cache_read_input_tokens')
    
    # Calculate current context usage (for percentage)
    current_context=$((input_tokens + cache_creation + cache_read))
    
    # Calculate context percentage
    if [ "$context_size" != "null" ] && [ "$context_size" -gt 0 ]; then
        context_pct=$((current_context * 100 / context_size))
    fi
    
    # Token display (current call)
    tokens_display="${input_tokens}in/${output_tokens}out"
    
    # Add cache info if present
    if [ "$cache_read" -gt 0 ] || [ "$cache_creation" -gt 0 ]; then
        tokens_display="${tokens_display} (cr:${cache_creation}/rd:${cache_read})"
    fi
    
    # Calculate cost based on model
    # Pricing (per 1M tokens):
    # Sonnet 3.5: $3 input, $15 output
    # Opus 4.5: $15 input, $75 output
    # Haiku 3.5: $1 input, $5 output
    # Cache write: 1.25x input, Cache read: 0.1x input
    
    case "$model_id" in
        *"opus"*"4"*)
            input_price=15
            output_price=75
            ;;
        *"sonnet"*"3.5"*|*"sonnet"*"4"*)
            input_price=3
            output_price=15
            ;;
        *"haiku"*)
            input_price=1
            output_price=5
            ;;
        *)
            input_price=3
            output_price=15
            ;;
    esac
    
    # Calculate cost in dollars (using bc for floating point)
    input_cost=$(echo "scale=6; $input_tokens * $input_price / 1000000" | bc)
    output_cost=$(echo "scale=6; $output_tokens * $output_price / 1000000" | bc)
    cache_write_cost=$(echo "scale=6; $cache_creation * $input_price * 1.25 / 1000000" | bc)
    cache_read_cost=$(echo "scale=6; $cache_read * $input_price * 0.1 / 1000000" | bc)
    
    total_cost=$(echo "scale=4; $input_cost + $output_cost + $cache_write_cost + $cache_read_cost" | bc)
    
    # Format cost display
    cost_display=$(printf "\$%.4f" $total_cost)
fi

# Get directory name (basename)
dir_name=$(basename "$cwd")

# Context color based on percentage
if [ "$context_pct" -ge 80 ]; then
    ctx_color="$RED"
elif [ "$context_pct" -ge 50 ]; then
    ctx_color="$YELLOW"
else
    ctx_color="$GREEN"
fi

# Color selection function
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

session_color=$(select_color "$five_hour_pct")
week_color=$(select_color "$seven_day_pct")
sonnet_color=$(select_color "$seven_day_sonnet_pct")

# Format reset time displays
session_reset_str=""
[ -n "$session_reset_display" ] && session_reset_str=" (${session_reset_display})"

week_reset_str=""
[ -n "$week_reset_display" ] && week_reset_str=" (${week_reset_display})"

# Format output with colors
# Format: Model | Ctx: X% | Session: X% (HH:MMpm) | Week: All X% / Sonnet X% (MonDD HH:MMpm)
printf "${CYAN}%s${RESET} ${DIM}|${RESET} Ctx: ${ctx_color}%d%%${RESET} ${DIM}|${RESET} Session: ${session_color}%d%%${RESET}${DIM}%s${RESET} ${DIM}|${RESET} Week: All ${week_color}%d%%${RESET} / Sonnet ${sonnet_color}%d%%${RESET}${DIM}%s${RESET}" \
    "$model_name" \
    "$context_pct" \
    "$five_hour_pct" \
    "$session_reset_str" \
    "$seven_day_pct" \
    "$seven_day_sonnet_pct" \
    "$week_reset_str"
