#!/bin/bash
# workflow-gate.sh - D→R→T 強制阻擋
# 事件: PreToolUse (Task)
# 功能: 確保程式碼變更經過 DEVELOPER → REVIEWER → TESTER
# 2025 AI Guardrails: Runtime Enforcer Pattern
# 支援: 並行任務隔離（基於 Change ID）+ 時間戳過期機制

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)

# 狀態目錄
STATE_DIR="${PWD}/.claude"
mkdir -p "$STATE_DIR" 2>/dev/null

# 狀態過期時間（秒）- 30 分鐘
STATE_EXPIRY=1800

# 解析 Task 的 subagent_type 和 prompt
SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' | tr '[:upper:]' '[:lower:]')
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')

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
        LAST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_TIMESTAMP" "+%s" 2>/dev/null || date -d "$LAST_TIMESTAMP" "+%s" 2>/dev/null || echo 0)
        NOW_EPOCH=$(date "+%s")
        AGE=$((NOW_EPOCH - LAST_EPOCH))

        if [ $AGE -lt $STATE_EXPIRY ]; then
            STATE_VALID=true
        fi
    fi
fi

# 顯示 Change ID（如果有）
if [ -n "$CHANGE_ID" ]; then
    echo "📌 Change: $CHANGE_ID"
fi

# D→R→T 流程控制
case "$SUBAGENT_TYPE" in
    developer)
        # DEVELOPER 可以：
        # 1. 直接啟動（起點）
        # 2. REVIEWER REJECT 後重新啟動（修復）
        # 3. TESTER FAIL 後重新啟動（修復）
        if [ "$STATE_VALID" = true ]; then
            if [ "$LAST_AGENT" = "reviewer" ] && [ "$LAST_RESULT" = "reject" ]; then
                echo "🔄 DEVELOPER 重新啟動（REVIEWER 要求修改）"
            elif [ "$LAST_AGENT" = "tester" ] && [ "$LAST_RESULT" = "fail" ]; then
                echo "🔄 DEVELOPER 重新啟動（TESTER 發現問題）"
            elif [ "$LAST_AGENT" = "debugger" ]; then
                echo "🔄 DEVELOPER 重新啟動（DEBUGGER 提供修復方案）"
            else
                echo "📝 DEVELOPER 啟動"
            fi
        else
            echo "📝 DEVELOPER 啟動"
        fi
        echo ""
        echo "💡 完成後需要 REVIEWER 審查"
        ;;

    reviewer)
        # REVIEWER 應該在 DEVELOPER 後啟動
        if [ "$STATE_VALID" = true ] && [ "$LAST_AGENT" != "developer" ] && [ -n "$LAST_AGENT" ]; then
            echo "⚠️ 提示：REVIEWER 通常在 DEVELOPER 完成後啟動"
            echo "   目前上一個 Agent: $LAST_AGENT ($LAST_RESULT)"
        fi
        echo "🔍 REVIEWER 啟動"
        ;;

    tester)
        # TESTER 必須在 REVIEWER APPROVE 後啟動
        # 阻擋條件：上一個是 DEVELOPER（跳過審查）且狀態有效
        if [ "$STATE_VALID" = true ] && [ "$LAST_AGENT" = "developer" ]; then
            echo "╔════════════════════════════════════════════════════════════════╗"
            echo "║                   ❌ 流程違規                                   ║"
            echo "╚════════════════════════════════════════════════════════════════╝"
            echo ""
            echo "🚫 不允許跳過 REVIEWER 直接進行測試"
            echo ""
            echo "📋 正確流程:"
            echo "   DEVELOPER → REVIEWER → TESTER"
            echo "       ↓           ↓"
            echo "    實作完成    APPROVE 後才能測試"
            echo ""
            echo "💡 請先委派 REVIEWER 審查程式碼"
            # 輸出 block decision
            echo '{"decision":"block","reason":"跳過 REVIEWER 審查，違反 D→R→T 流程"}'
            exit 0
        fi

        # 警告條件：狀態無效或 REVIEWER 未明確 APPROVE
        if [ "$STATE_VALID" = false ]; then
            echo "⚠️ 注意：無法驗證流程狀態（可能已過期或首次執行）"
        elif [ "$LAST_AGENT" = "reviewer" ] && [ "$LAST_RESULT" != "approve" ]; then
            echo "⚠️ 注意：REVIEWER 結果為 '$LAST_RESULT'，非 APPROVE"
            echo "   建議確認 REVIEWER 已通過審查"
        fi

        echo "🧪 TESTER 啟動"
        ;;

    debugger)
        # DEBUGGER 通常在 TESTER FAIL 後啟動
        if [ "$STATE_VALID" = true ] && [ "$LAST_AGENT" = "tester" ] && [ "$LAST_RESULT" = "fail" ]; then
            echo "🐛 DEBUGGER 啟動（分析測試失敗）"
        else
            echo "🐛 DEBUGGER 啟動"
        fi
        ;;

    architect)
        echo "🏗️ ARCHITECT 啟動"
        ;;

    designer)
        echo "🎨 DESIGNER 啟動"
        ;;

    planner|plan)
        echo "📋 PLANNER 啟動"
        ;;

    explorer|explore)
        echo "🔍 EXPLORER 啟動"
        ;;

    *)
        # 其他 agent 允許通過
        echo "📋 Agent '$SUBAGENT_TYPE' 啟動"
        ;;
esac

# 允許通過（除非已經輸出 block decision）
exit 0
