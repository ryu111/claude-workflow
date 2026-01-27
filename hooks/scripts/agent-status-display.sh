#!/bin/bash
# agent-status-display.sh - Agent 啟動視覺確認
# 事件: SubagentStart
# 功能: 當 Agent 啟動時顯示即時確認給用戶
# 2025 AI Guardrails: User Notification Pattern

# DEBUG
DEBUG_LOG="/tmp/claude-workflow-debug.log"
echo "[$(date)] agent-status-display.sh called (SubagentStart)" >> "$DEBUG_LOG"

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)
echo "[$(date)] SubagentStart INPUT: $INPUT" >> "$DEBUG_LOG"

# 解析 Agent 名稱（格式：claude-workflow:developer）
# 注意：SubagentStart 事件使用 .agent_type，不是 .agent_name
RAW_AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_type // empty' | tr '[:upper:]' '[:lower:]')
# 移除 plugin 前綴
AGENT_NAME=$(echo "$RAW_AGENT_NAME" | sed 's/.*://')

# 解析任務描述（優先使用 agent_description，fallback 到 description）
DESCRIPTION=$(echo "$INPUT" | jq -r '.agent_description // .description // empty')

echo "[$(date)] AGENT_NAME: $AGENT_NAME, DESCRIPTION: $DESCRIPTION" >> "$DEBUG_LOG"

# 如果沒有 agent 名稱，直接退出
if [ -z "$AGENT_NAME" ]; then
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
# 設定當前 Agent 狀態檔案（供 global-workflow-guard.sh 使用）
# ═══════════════════════════════════════════════════════════════

SESSION_ID="${CLAUDE_SESSION_ID:-default}"
AGENT_STATE_FILE="/tmp/claude-agent-state-${SESSION_ID}"

# 寫入當前 agent 名稱
echo "$AGENT_NAME" > "$AGENT_STATE_FILE"
echo "[$(date)] Set current agent to: $AGENT_NAME (file: $AGENT_STATE_FILE)" >> "$DEBUG_LOG"

# ═══════════════════════════════════════════════════════════════
# 使用 JSON additionalContext 注入 Agent 資訊（Claude 可見）
# ═══════════════════════════════════════════════════════════════

# 建構 additionalContext 訊息
CONTEXT_MSG="🤖 Agent 啟動: $AGENT_NAME"
if [ -n "$DESCRIPTION" ]; then
    CONTEXT_MSG="$CONTEXT_MSG | 任務: $DESCRIPTION"
fi

# 輸出 JSON（這會注入到 Claude 的上下文）
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": "$CONTEXT_MSG"
  }
}
EOF

exit 0
