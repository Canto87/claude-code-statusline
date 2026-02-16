<h1 align="center">claude-code-statusline</h1>

<p align="center">
  <strong>Claude Code リアルタイムサブスクリプション使用量モニタリング</strong>
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
  Claude Max/Pro サブスクリプションの使用量をステータスラインにリアルタイム表示。<br>
  セッション上限、週間上限、コンテキストウィンドウ — すべてを一目で確認。
</p>

<p align="center">
  <img src="screenshot.png" alt="Screenshot">
</p>

---

## 課題

Claude Code の `/usage` コマンドはサブスクリプション上限を表示しますが：

- **作業中は見えない** — 確認するたびに `/usage` と入力する必要がある
- **上限到達前の警告がない** — リクエスト失敗後にレート制限に気づく
- **コンテキストが不透明** — コンパクションが起きるまで残量がわからない

## 解決策

`claude-code-statusline` は使用量データを常に見える場所に表示します：

```
  Opus 4.5 | Ctx: 44% | Session: 77% (10:59pm) | Week: All 7% / Sonnet 1% (Jan17 5:59pm)
  ────────   ────────   ──────────────────────   ─────────────────────────────────────────
  モデル     コンテキスト  5時間サイクル使用量 +   7日間上限（全モデル + Sonnet 内訳）
             ウィンドウ %  リセット時刻            + リセット時刻
```

上限に近づくにつれて色が変化 — 緑 → 黄 → 赤。

## クイックスタート

```bash
# ダウンロード
curl -o ~/.claude/statusline-command.sh \
  https://raw.githubusercontent.com/Canto87/claude-code-statusline/main/statusline-command.sh

# 実行権限を付与
chmod +x ~/.claude/statusline-command.sh
```

`~/.claude/settings.json` に追加：

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

> **必要条件:** macOS、`jq`、`curl`、Claude Code Pro/Max サブスクリプション

## 仕組み

```
  Claude Code がステータスラインコマンドを実行
       │
       ▼
  macOS キーチェーンから OAuth トークンを読み取り
       │
       ▼
  GET /api/oauth/usage ──► レスポンスをキャッシュ（60秒 TTL）
       │
       ▼
  使用率 % + リセット時刻をパース
       │
       ▼
  ANSI カラーでフォーマット ──► ステータスラインに表示
```

スクリプトは `/usage` が内部で使用するのと同じ API を呼び出します：

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <oauth_token>
```

OAuth トークンは Claude Code が保存した macOS キーチェーンから読み取ります。手動でのトークン設定は不要です。

## 出力フォーマット

| フィールド | 説明 | カラー閾値 |
|:-----------|:-----|:-----------|
| Model | 現在の Claude モデル | Cyan（常時） |
| Ctx | コンテキストウィンドウ使用率 % | 🟢 <50% · 🟡 50-79% · 🔴 80%+ |
| Session | 5時間サイクル使用量 + リセット時刻 | 🟢 <50% · 🟡 50-79% · 🔴 80%+ |
| Week All | 7日間全モデル使用量 | 🟢 <50% · 🟡 50-79% · 🔴 80%+ |
| Week Sonnet | 7日間 Sonnet 専用使用量 + リセット時刻 | 🟢 <50% · 🟡 50-79% · 🔴 80%+ |

API 呼び出し失敗時（トークン期限切れ、ネットワーク障害など）は、誤解を招く 0% ではなく `Usage: API Error` を表示します。

## カスタマイズ

### キャッシュ期間

スクリプトの `CACHE_MAX_AGE` を編集（デフォルト: 60秒）：

```bash
CACHE_MAX_AGE=120  # 2分
```

### カラー閾値

`select_color` 関数を編集：

```bash
select_color() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then    # 90%+ で赤
        echo "$RED"
    elif [ "$pct" -ge 70 ]; then  # 70%+ で黄
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}
```

## トラブルシューティング

### ステータスラインが表示されない

スクリプトを直接テスト：

```bash
echo '{}' | ~/.claude/statusline-command.sh
```

### "API Error" が表示される

OAuth トークンへのアクセスを確認：

```bash
security find-generic-password -s "Claude Code-credentials" -w | jq '.claudeAiOauth.accessToken' | head -c 20
```

空の場合、Claude Code で `/login` を実行して再ログイン。

### 使用量が常に 0% と表示される

古いキャッシュを削除して再試行：

```bash
rm ~/.claude/usage-cache.json
```

## ライセンス

[MIT](LICENSE)
