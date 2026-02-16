<h1 align="center">claude-code-statusline</h1>

<p align="center">
  <strong>Claude Code 실시간 구독 사용량 모니터링</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/shell-bash-green.svg" alt="Shell: Bash">
  <img src="https://img.shields.io/badge/requires-Claude%20Code%20CLI-blueviolet.svg" alt="Requires Claude Code">
  <br>
  <a href="README.md"><img src="https://img.shields.io/badge/🇺🇸_English-white.svg" alt="English"></a>
  <a href="README.ko.md"><img src="https://img.shields.io/badge/🇰🇷_한국어-white.svg" alt="한국어"></a>
  <a href="README.ja.md"><img src="https://img.shields.io/badge/🇯🇵_日本語-white.svg" alt="日本語"></a>
</p>

<p align="center">
  Claude Max/Pro 구독 사용량을 스테이터스 라인에 실시간으로 표시합니다.<br>
  세션 한도, 주간 한도, 컨텍스트 윈도우 — 한눈에 확인.
</p>

<p align="center">
  <img src="screenshot.png" alt="Screenshot">
</p>

---

## 문제

Claude Code의 `/usage` 명령은 구독 한도를 보여주지만:

- **작업 중 보이지 않음** — 확인하려면 매번 `/usage`를 입력해야 함
- **한도 초과 전 경고 없음** — 요청이 실패한 후에야 레이트 리밋에 걸렸다는 걸 알게 됨
- **컨텍스트 블라인드** — 컴팩션이 일어날 때까지 얼마나 가까운지 알 수 없음

## 해결

`claude-code-statusline`은 사용량 데이터를 항상 보이는 곳에 표시합니다:

```
  Opus 4.5 | Ctx: 44% | Session: 77% (10:59pm) | Week: All 7% / Sonnet 1% (Jan17 5:59pm)
  ────────   ────────   ──────────────────────   ─────────────────────────────────────────
  모델       컨텍스트   5시간 주기 사용량 +      7일 한도 (전체 모델 + Sonnet 별도)
             윈도우 %   리셋 시간                + 리셋 시간
```

한도에 가까워질수록 색상이 바뀝니다 — 초록 → 노랑 → 빨강.

## 빠른 시작

```bash
# 다운로드
curl -o ~/.claude/statusline-command.sh \
  https://raw.githubusercontent.com/Canto87/claude-code-statusline/main/statusline-command.sh

# 실행 권한 부여
chmod +x ~/.claude/statusline-command.sh
```

`~/.claude/settings.json`에 추가:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

> **필수 요건:** macOS, `jq`, `curl`, Claude Code Pro/Max 구독

## 작동 방식

```
  Claude Code가 스테이터스 라인 커맨드 실행
       │
       ▼
  macOS 키체인에서 OAuth 토큰 읽기
       │
       ▼
  GET /api/oauth/usage ──► 응답 캐시 (60초 TTL)
       │
       ▼
  사용률 % + 리셋 시간 파싱
       │
       ▼
  ANSI 색상 포맷팅 ──► 스테이터스 라인에 표시
```

스크립트는 `/usage`가 내부적으로 사용하는 동일한 API를 호출합니다:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <oauth_token>
```

OAuth 토큰은 Claude Code가 저장한 macOS 키체인에서 읽습니다. 수동 토큰 설정이 필요 없습니다.

## 출력 형식

| 필드 | 설명 | 색상 임계값 |
|:-----|:-----|:------------|
| Model | 현재 Claude 모델 | Cyan (항상) |
| Ctx | 컨텍스트 윈도우 사용률 % | 🟢 <50% · 🟡 50-79% · 🔴 80%+ |
| Session | 5시간 주기 사용량 + 리셋 시간 | 🟢 <50% · 🟡 50-79% · 🔴 80%+ |
| Week All | 7일 전체 모델 사용량 | 🟢 <50% · 🟡 50-79% · 🔴 80%+ |
| Week Sonnet | 7일 Sonnet 전용 사용량 + 리셋 시간 | 🟢 <50% · 🟡 50-79% · 🔴 80%+ |

API 호출 실패 시 (만료된 토큰, 네트워크 문제 등) 오해의 소지가 있는 0% 대신 `Usage: API Error`를 표시합니다.

## 커스터마이징

### 캐시 기간

스크립트의 `CACHE_MAX_AGE`를 수정 (기본: 60초):

```bash
CACHE_MAX_AGE=120  # 2분
```

### 색상 임계값

`select_color` 함수를 수정:

```bash
select_color() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then    # 90%+에서 빨강
        echo "$RED"
    elif [ "$pct" -ge 70 ]; then  # 70%+에서 노랑
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}
```

## 트러블슈팅

### 스테이터스 라인이 표시되지 않음

스크립트를 직접 테스트:

```bash
echo '{}' | ~/.claude/statusline-command.sh
```

### "API Error" 표시

OAuth 토큰 접근 가능 여부 확인:

```bash
security find-generic-password -s "Claude Code-credentials" -w | jq '.claudeAiOauth.accessToken' | head -c 20
```

비어 있다면 Claude Code에서 `/login`으로 재로그인.

### 사용량이 항상 0% 표시

오래된 캐시를 삭제하고 재시도:

```bash
rm ~/.claude/usage-cache.json
```

## 라이선스

[MIT](LICENSE)
