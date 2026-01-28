#!/bin/bash
# Session State Cleanup - 清理 Agent 狀態追蹤
# 用途：在 SessionEnd 時移除狀態檔案

STATE_FILE="/tmp/claude-agent-state-${CLAUDE_SESSION_ID:-default}"
rm -f "$STATE_FILE"
