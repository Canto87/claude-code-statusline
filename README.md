# Claude Code Status Line with Real-time Usage Limits

Display your Claude Max/Pro subscription usage directly in the Claude Code status line.

![Screenshot](screenshot.png)

## Features

- **Real-time subscription usage** from Anthropic API (same as `/usage` command)
- **Color-coded warnings**:
  - 🟢 Green: 0-49%
  - 🟡 Yellow: 50-79%
  - 🔴 Red: 80%+
- **60-second cache** to minimize API calls
- **Context window usage** tracking

## Output Format

```
Opus 4.5 | Ctx: 40% | Session: 63% | Week: 5% | my-project
```

| Field | Description |
|-------|-------------|
| Model | Current Claude model (cyan) |
| Ctx | Context window usage % |
| Session | 5-hour cycle usage % (resets every 5 hours) |
| Week | 7-day usage % (resets weekly) |
| Directory | Current working directory |

## Requirements

- macOS (uses Keychain for OAuth token)
- `jq` (JSON parser)
- `curl`
- Claude Code with Pro/Max subscription

## Installation

### Quick Install (one-liner)

```bash
curl -o ~/.claude/statusline-command.sh https://raw.githubusercontent.com/YOUR_USERNAME/claude-code-statusline/main/statusline-command.sh && \
chmod +x ~/.claude/statusline-command.sh && \
echo '{"statusLine":{"type":"command","command":"~/.claude/statusline-command.sh"}}' > ~/.claude/settings.json
```

### Manual Install

1. Download the script:
```bash
curl -o ~/.claude/statusline-command.sh https://raw.githubusercontent.com/YOUR_USERNAME/claude-code-statusline/main/statusline-command.sh
```

2. Make it executable:
```bash
chmod +x ~/.claude/statusline-command.sh
```

3. Add to `~/.claude/settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

## How It Works

The script calls the Anthropic OAuth usage API:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <oauth_token>
```

The OAuth token is retrieved from macOS Keychain where Claude Code stores it.

### API Response Example

```json
{
  "five_hour": {
    "utilization": 58,
    "resets_at": "2026-01-10T14:00:00+00:00"
  },
  "seven_day": {
    "utilization": 5,
    "resets_at": "2026-01-17T09:00:00+00:00"
  }
}
```

## Customization

### Change Cache Duration

Edit `CACHE_MAX_AGE` in the script (default: 60 seconds):

```bash
CACHE_MAX_AGE=120  # 2 minutes
```

### Change Color Thresholds

Edit the `select_color` function:

```bash
select_color() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then    # Red at 90%+
        echo "$RED"
    elif [ "$pct" -ge 70 ]; then  # Yellow at 70%+
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}
```

## Troubleshooting

### Status line not showing

Check if the script works:
```bash
echo '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/test"},"context_window":{"context_window_size":200000,"current_usage":null}}' | ~/.claude/statusline-command.sh
```

### Usage always shows 0%

- Make sure you're logged into Claude Code (`/login`)
- Check if OAuth token exists:
```bash
security find-generic-password -s "Claude Code-credentials" -w
```

## License

MIT

## Contributing

Issues and PRs welcome!
