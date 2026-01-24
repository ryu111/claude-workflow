#!/bin/bash
# workflow-gate.sh - D→R→T 強制阻擋
# 事件: PreToolUse (Task)
# 功能: 確保程式碼變更經過 DEVELOPER → REVIEWER → TESTER
# 2025 AI Guardrails: Runtime Enforcer Pattern
# 支援: 並行任務隔離（基於 Change ID）+ 時間戳過期機制
# 支援: Bypass 機制（開發測試用）

# DEBUG: 記錄 hook 被呼叫
echo "[$(date)] workflow-gate.sh called" >> /tmp/claude-workflow-debug.log

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)
echo "[$(date)] INPUT: $INPUT" >> /tmp/claude-workflow-debug.log

# 狀態目錄
STATE_DIR="${PWD}/.claude"
mkdir -p "$STATE_DIR" 2>/dev/null

# Bypass 配置文件
BYPASS_FILE="${STATE_DIR}/.drt-bypass"

# 檢查 Bypass 模式
BYPASS_MODE=false
BYPASS_REASON=""

# 方式 1: 環境變數
if [ "$CLAUDE_WORKFLOW_BYPASS" = "true" ] || [ "$CLAUDE_WORKFLOW_BYPASS" = "1" ]; then
    BYPASS_MODE=true
    BYPASS_REASON="環境變數 CLAUDE_WORKFLOW_BYPASS"
fi

# 方式 2: 配置文件
if [ -f "$BYPASS_FILE" ]; then
    BYPASS_MODE=true
    BYPASS_REASON="配置文件 .claude/.drt-bypass"
fi

# 如果啟用 Bypass，記錄並跳過所有檢查
if [ "$BYPASS_MODE" = true ]; then
    echo "[$(date)] BYPASS MODE ENABLED: $BYPASS_REASON" >> /tmp/claude-workflow-debug.log
    echo "⚡ Bypass 模式已啟用（$BYPASS_REASON）"
    echo "⚠️ D→R→T 流程檢查已跳過"
    exit 0
fi

# 狀態過期時間（秒）- 30 分鐘
STATE_EXPIRY=1800

# 解析 Task 的 subagent_type 和 prompt
RAW_SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' | tr '[:upper:]' '[:lower:]')
# 移除 plugin 前綴（如 "claude-workflow:developer" → "developer"）
SUBAGENT_TYPE=$(echo "$RAW_SUBAGENT_TYPE" | sed 's/.*://')
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')

echo "[$(date)] SUBAGENT_TYPE: $SUBAGENT_TYPE (raw: $RAW_SUBAGENT_TYPE)" >> /tmp/claude-workflow-debug.log

# 如果不是 Task 工具或沒有 subagent_type，允許通過
if [ -z "$SUBAGENT_TYPE" ]; then
    exit 0
fi

# 嘗試從 prompt 中解析 Change ID（支援多種格式）
CHANGE_ID=""
if [ -n "$PROMPT" ]; then
    # 格式: [change-id], change: change-id, #change-id
    CHANGE_ID=$(echo "$PROMPT" | grep -oE '\[([a-zA-Z0-9_-]+)\]' | head -1 | tr -d '[]')
    if [ -z "$CHANGE_ID" ]; then
        CHANGE_ID=$(echo "$PROMPT" | grep -oiE 'change[:\s]+([a-zA-Z0-9_-]+)' | head -1 | sed 's/[cC]hange[: ]*//')
    fi
    if [ -z "$CHANGE_ID" ]; then
        CHANGE_ID=$(echo "$PROMPT" | grep -oE '#([a-zA-Z0-9_-]+)' | head -1 | tr -d '#')
    fi
fi

# 決定狀態檔案路徑
if [ -n "$CHANGE_ID" ]; then
    # 有 Change ID：使用獨立狀態檔案
    STATE_FILE="${STATE_DIR}/.drt-state-${CHANGE_ID}"
else
    # 無 Change ID：使用全域狀態檔案
    STATE_FILE="${STATE_DIR}/.drt-workflow-state"
fi

# 讀取上一個 agent 狀態
LAST_AGENT=""
LAST_RESULT=""
LAST_TIMESTAMP=""
STATE_VALID=false

if [ -f "$STATE_FILE" ]; then
    LAST_AGENT=$(jq -r '.agent // empty' "$STATE_FILE" 2>/dev/null)
    LAST_RESULT=$(jq -r '.result // empty' "$STATE_FILE" 2>/dev/null)
    LAST_TIMESTAMP=$(jq -r '.timestamp // empty' "$STATE_FILE" 2>/dev/null)

    # 檢查狀態是否過期
    if [ -n "$LAST_TIMESTAMP" ]; then
        # macOS: date -ju (BSD), Linux: date -d (GNU)
        LAST_EPOCH=$(date -ju -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_TIMESTAMP" "+%s" 2>/dev/null || date -d "$LAST_TIMESTAMP" "+%s" 2>/dev/null || echo 0)
        NOW_EPOCH=$(date "+%s")
        AGE=$((NOW_EPOCH - LAST_EPOCH))

        if [ $AGE -lt $STATE_EXPIRY ]; then
            STATE_VALID=true
        fi
    fi
fi

# 顯示 Change ID（如果有）
if [ -n "$CHANGE_ID" ]; then
    echo "📌 Change: $CHANGE_ID" >&2
fi

# D→R→T 流程控制（所有訊息輸出到 stderr 以顯示給用戶）
case "$SUBAGENT_TYPE" in
    developer)
        # DEVELOPER 可以：
        # 1. 直接啟動（起點）
        # 2. REVIEWER REJECT 後重新啟動（修復）
        # 3. TESTER FAIL 後重新啟動（修復）
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════════╗" >&2
        if [ "$STATE_VALID" = true ]; then
            if [ "$LAST_AGENT" = "reviewer" ] && [ "$LAST_RESULT" = "reject" ]; then
                echo "║            🔄 DEVELOPER 重新啟動（修復中）                       ║" >&2
            elif [ "$LAST_AGENT" = "tester" ] && [ "$LAST_RESULT" = "fail" ]; then
                echo "║            🔄 DEVELOPER 重新啟動（修復中）                       ║" >&2
            elif [ "$LAST_AGENT" = "debugger" ]; then
                echo "║            🔄 DEVELOPER 重新啟動（修復中）                       ║" >&2
            else
                echo "║                    💻 DEVELOPER 啟動                            ║" >&2
            fi
        else
            echo "║                    💻 DEVELOPER 啟動                            ║" >&2
        fi
        echo "╚════════════════════════════════════════════════════════════════╝" >&2
        echo "📚 Skills: drt-rules, development, ui-design, checkpoint" >&2
        echo "💡 完成後需要 REVIEWER 審查" >&2
        echo "" >&2
        ;;

    reviewer)
        # REVIEWER 應該在 DEVELOPER 後啟動
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════════╗" >&2
        echo "║                    🔍 REVIEWER 啟動                             ║" >&2
        echo "╚════════════════════════════════════════════════════════════════╝" >&2
        if [ "$STATE_VALID" = true ] && [ "$LAST_AGENT" != "developer" ] && [ -n "$LAST_AGENT" ]; then
            echo "⚠️ 提示：REVIEWER 通常在 DEVELOPER 完成後啟動" >&2
        fi
        echo "📚 Skills: drt-rules, code-review" >&2
        echo "🔒 唯讀模式：僅可使用 Read, Glob, Grep" >&2
        echo "" >&2
        ;;

    tester)
        # TESTER 必須在 REVIEWER APPROVE 後啟動
        # 阻擋條件：上一個是 DEVELOPER（跳過審查）且狀態有效
        if [ "$STATE_VALID" = true ] && [ "$LAST_AGENT" = "developer" ]; then
            # 文字訊息輸出到 stderr（顯示給用戶）
            echo "╔════════════════════════════════════════════════════════════════╗" >&2
            echo "║                   ❌ 流程違規                                   ║" >&2
            echo "╚════════════════════════════════════════════════════════════════╝" >&2
            echo "" >&2
            echo "🚫 不允許跳過 REVIEWER 直接進行測試" >&2
            echo "" >&2
            echo "📋 正確流程:" >&2
            echo "   DEVELOPER → REVIEWER → TESTER" >&2
            echo "       ↓           ↓" >&2
            echo "    實作完成    APPROVE 後才能測試" >&2
            echo "" >&2
            echo "💡 請先委派 REVIEWER 審查程式碼" >&2
            # JSON decision 輸出到 stdout（Claude Code 解析）
            echo '{"decision":"block","reason":"跳過 REVIEWER 審查，違反 D→R→T 流程"}'
            exit 0
        fi

        # 警告條件：狀態無效或 REVIEWER 未明確 APPROVE
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════════╗" >&2
        echo "║                    🧪 TESTER 啟動                               ║" >&2
        echo "╚════════════════════════════════════════════════════════════════╝" >&2
        if [ "$STATE_VALID" = false ]; then
            echo "⚠️ 注意：無法驗證流程狀態（可能已過期）" >&2
        elif [ "$LAST_AGENT" = "reviewer" ] && [ "$LAST_RESULT" != "approve" ]; then
            echo "⚠️ REVIEWER 結果為 '$LAST_RESULT'，非 APPROVE" >&2
        fi
        echo "📚 Skills: drt-rules, test, error-handling" >&2
        echo "🧰 工具：Read, Glob, Grep, Bash" >&2
        echo "" >&2
        ;;

    debugger)
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════════╗" >&2
        echo "║                    🐛 DEBUGGER 啟動                             ║" >&2
        echo "╚════════════════════════════════════════════════════════════════╝" >&2
        if [ "$STATE_VALID" = true ] && [ "$LAST_AGENT" = "tester" ] && [ "$LAST_RESULT" = "fail" ]; then
            echo "📋 分析測試失敗原因" >&2
        fi
        echo "" >&2
        ;;

    architect)
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════════╗" >&2
        echo "║                    🏗️ ARCHITECT 啟動                            ║" >&2
        echo "╚════════════════════════════════════════════════════════════════╝" >&2
        echo "" >&2
        ;;

    designer)
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════════╗" >&2
        echo "║                    🎨 DESIGNER 啟動                             ║" >&2
        echo "╚════════════════════════════════════════════════════════════════╝" >&2
        echo "" >&2
        ;;

    planner|plan)
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════════╗" >&2
        echo "║                    📋 PLANNER 啟動                              ║" >&2
        echo "╚════════════════════════════════════════════════════════════════╝" >&2
        echo "" >&2
        ;;

    explorer|explore)
        echo "" >&2
        echo "╔════════════════════════════════════════════════════════════════╗" >&2
        echo "║                    🔭 EXPLORER 啟動                             ║" >&2
        echo "╚════════════════════════════════════════════════════════════════╝" >&2
        echo "" >&2
        ;;

    *)
        # 其他 agent 允許通過，不顯示大框
        echo "📋 Agent '$SUBAGENT_TYPE' 啟動" >&2
        ;;
esac

# 允許通過（除非已經輸出 block decision）
exit 0
