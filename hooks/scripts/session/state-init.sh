#!/bin/bash
# Session State Init - 初始化 Agent 狀態追蹤
# 用途：在 SessionStart 時設定初始狀態為 'main'

STATE_FILE="/tmp/claude-agent-state-${CLAUDE_SESSION_ID:-default}"
echo 'main' > "$STATE_FILE"
