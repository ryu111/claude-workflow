#!/bin/bash
# subagent-validator.sh - 驗證 Agent 輸出 + 記錄狀態
# 事件: SubagentStop 或 PostToolUse(Task)
# 功能: 確保 Agent 輸出符合預期格式，並記錄狀態供流程控制
# 2025 AI Guardrails: Post-hook Validation + State Management
# 支援: 並行任務隔離（基於 Change ID）

# DEBUG: 記錄 hook 被呼叫
echo "[$(date)] subagent-validator.sh called" >> /tmp/claude-workflow-debug.log

# ═══════════════════════════════════════════════════════════════
# E2E 統計記錄函數
# ═══════════════════════════════════════════════════════════════

# 取得 E2E 統計檔案路徑
get_e2e_stats_file() {
    local session_id="${E2E_SESSION_ID:-}"
    if [ -n "$session_id" ]; then
        echo "/tmp/claude-e2e-stats-${session_id}.jsonl"
    fi
}

# 記錄 E2E 重試事件
record_e2e_retry() {
    local agent="$1"
    local reason="$2"
    local retry_count="${3:-1}"

    local stats_file=$(get_e2e_stats_file)
    [ -z "$stats_file" ] && return  # 非 E2E 模式，跳過

    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "{\"type\":\"retry\",\"timestamp\":\"$timestamp\",\"agent\":\"$agent\",\"reason\":\"$reason\",\"retry_count\":$retry_count}" >> "$stats_file"
}

# 記錄 E2E 結果事件
record_e2e_result() {
    local agent="$1"
    local result="$2"
    local risk_level="${3:-MEDIUM}"
    local change_id="${4:-}"

    local stats_file=$(get_e2e_stats_file)
    [ -z "$stats_file" ] && return  # 非 E2E 模式，跳過

    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local json="{\"type\":\"result\",\"timestamp\":\"$timestamp\",\"agent\":\"$agent\",\"result\":\"$result\",\"risk_level\":\"$risk_level\""

    if [ -n "$change_id" ]; then
        json="$json,\"change_id\":\"$change_id\""
    fi

    json="$json}"

    echo "$json" >> "$stats_file"
}

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)
echo "[$(date)] Validator INPUT: $INPUT" >> /tmp/claude-workflow-debug.log

# 狀態目錄
STATE_DIR="${PWD}/.claude"
mkdir -p "$STATE_DIR" 2>/dev/null

# 檢測輸入來源（SubagentStop vs PostToolUse）
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
echo "[$(date)] Hook Event: $HOOK_EVENT" >> /tmp/claude-workflow-debug.log

# 解析 Agent 名稱和輸出（根據不同事件類型）
if [ "$HOOK_EVENT" = "PostToolUse" ]; then
    # PostToolUse(Task): 從 tool_input 獲取 subagent_type
    RAW_AGENT_NAME=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' | tr '[:upper:]' '[:lower:]')
    OUTPUT=$(echo "$INPUT" | jq -r '.tool_result // empty')
    PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')
else
    # SubagentStop: 從 agent_name 或讀取 transcript
    RAW_AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // .subagent_type // empty' | tr '[:upper:]' '[:lower:]')
    OUTPUT=$(echo "$INPUT" | jq -r '.output // empty')
    PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')
fi

# 移除 plugin 前綴（如 "claude-workflow:developer" → "developer"）
AGENT_NAME=$(echo "$RAW_AGENT_NAME" | sed 's/.*://')

echo "[$(date)] AGENT_NAME: $AGENT_NAME (raw: $RAW_AGENT_NAME)" >> /tmp/claude-workflow-debug.log

# 如果沒有 Agent 名稱，退出（不是我們的 plugin agent）
if [ -z "$AGENT_NAME" ]; then
    echo "[$(date)] No agent name found, skipping" >> /tmp/claude-workflow-debug.log
    exit 0
fi

# 嘗試從 prompt 或 output 中解析 Change ID
CHANGE_ID=""
# 先從 prompt 中找
if [ -n "$PROMPT" ]; then
    CHANGE_ID=$(echo "$PROMPT" | grep -oE '\[([a-zA-Z0-9_-]+)\]' | head -1 | tr -d '[]')
    if [ -z "$CHANGE_ID" ]; then
        CHANGE_ID=$(echo "$PROMPT" | grep -oiE 'change[:\s]+([a-zA-Z0-9_-]+)' | head -1 | sed 's/[cC]hange[: ]*//')
    fi
fi
# 如果 prompt 沒有，從 output 中找
if [ -z "$CHANGE_ID" ] && [ -n "$OUTPUT" ]; then
    CHANGE_ID=$(echo "$OUTPUT" | grep -oE '\[([a-zA-Z0-9_-]+)\]' | head -1 | tr -d '[]')
fi

# 任務 1: 如果無法解析 CHANGE_ID，自動生成唯一 ID
if [ -z "$CHANGE_ID" ]; then
    CHANGE_ID="auto-$(date +%s)-$RANDOM"
    echo "[$(date)] Auto-generated CHANGE_ID: $CHANGE_ID" >> /tmp/claude-workflow-debug.log
fi

# 決定狀態檔案路徑
if [ -n "$CHANGE_ID" ]; then
    STATE_FILE="${STATE_DIR}/.drt-state-${CHANGE_ID}"
else
    STATE_FILE="${STATE_DIR}/.drt-workflow-state"
fi

# 初始化結果
RESULT="unknown"

# 任務 2: 原子寫入輔助函數
atomic_write_state() {
    local content="$1"
    local target_file="$2"
    local temp_file="${target_file}.tmp.$$"

    # 寫入臨時檔案
    echo "$content" > "$temp_file"

    # 原子替換（mv 是原子操作）
    mv "$temp_file" "$target_file"

    # 添加檔案鎖定（如果 flock 可用）
    if command -v flock &> /dev/null; then
        flock -x "$target_file" -c "cat $target_file > /dev/null"
    fi
}

# 輔助函數：讀取現有失敗次數
get_fail_count() {
    if [ -f "$STATE_FILE" ]; then
        local count=$(jq -r '.fail_count // 0' "$STATE_FILE" 2>/dev/null)
        echo "${count:-0}"
    else
        echo "0"
    fi
}

# 任務 4: 輔助函數：讀取 REJECT 次數
get_reject_count() {
    if [ -f "$STATE_FILE" ]; then
        local count=$(jq -r '.reject_count // 0' "$STATE_FILE" 2>/dev/null)
        echo "${count:-0}"
    else
        echo "0"
    fi
}

# 輔助函數：讀取風險等級
get_risk_level() {
    if [ -f "$STATE_FILE" ]; then
        local level=$(jq -r '.risk_level // "MEDIUM"' "$STATE_FILE" 2>/dev/null)
        echo "${level:-MEDIUM}"
    else
        echo "MEDIUM"
    fi
}

# 任務 9: 輔助函數：記錄狀態（包含版本號）
record_state() {
    local agent=$1
    local result=$2
    local change_id=$3
    local fail_count=${4:-0}
    local risk_level=${5:-"MEDIUM"}
    local reject_count=${6:-0}

    local json="{\"version\":\"1.0\",\"agent\":\"$agent\",\"result\":\"$result\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    if [ -n "$change_id" ]; then
        json="$json,\"change_id\":\"$change_id\""
    fi
    json="$json,\"fail_count\":$fail_count,\"reject_count\":$reject_count,\"risk_level\":\"$risk_level\"}"

    # 使用原子寫入
    atomic_write_state "$json" "$STATE_FILE"
}

# 根據 Agent 類型驗證輸出並記錄狀態
case "$AGENT_NAME" in
    developer)
        # 檢查是否有變更摘要
        if echo "$OUTPUT" | grep -qi "修改檔案\|變更摘要\|完成\|implemented\|created\|updated"; then
            echo "✅ DEVELOPER 輸出格式正確"
            RESULT="complete"
        else
            echo "⚠️ DEVELOPER 輸出建議包含變更摘要"
            echo "   建議格式："
            echo "   - 修改檔案：列出變更的檔案"
            echo "   - 變更說明：描述做了什麼"
            RESULT="incomplete"
        fi

        # 保留現有的失敗計數、REJECT 計數和風險等級
        CURRENT_FAIL_COUNT=$(get_fail_count)
        CURRENT_REJECT_COUNT=$(get_reject_count)
        CURRENT_RISK_LEVEL=$(get_risk_level)

        # 記錄狀態
        record_state "developer" "$RESULT" "$CHANGE_ID" "$CURRENT_FAIL_COUNT" "$CURRENT_RISK_LEVEL" "$CURRENT_REJECT_COUNT"

        echo ""
        echo "╭─────────────────────────────────────────╮"
        echo "│ 📋 下一步: 請委派 REVIEWER 審查         │"
        echo "╰─────────────────────────────────────────╯"
        ;;

    reviewer)
        # 保留現有的失敗計數和風險等級
        CURRENT_FAIL_COUNT=$(get_fail_count)
        CURRENT_REJECT_COUNT=$(get_reject_count)
        CURRENT_RISK_LEVEL=$(get_risk_level)

        # 檢查是否有 Verdict
        if echo "$OUTPUT" | grep -qi "APPROVED\|APPROVE\|通過\|批准"; then
            echo "✅ REVIEWER APPROVED"
            RESULT="approve"

            # E2E 統計：記錄結果
            record_e2e_result "reviewer" "approve" "$CURRENT_RISK_LEVEL" "$CHANGE_ID"

            # APPROVE 時重置 reject_count
            record_state "reviewer" "$RESULT" "$CHANGE_ID" "$CURRENT_FAIL_COUNT" "$CURRENT_RISK_LEVEL" 0

            echo ""
            echo "╭─────────────────────────────────────────╮"
            echo "│ 📋 下一步: 請委派 TESTER 測試          │"
            echo "╰─────────────────────────────────────────╯"

        elif echo "$OUTPUT" | grep -qi "REJECT\|REQUEST CHANGES\|需要修改\|駁回"; then
            echo "🔄 REVIEWER REQUEST CHANGES"
            RESULT="reject"

            # 任務 4: 增加 REJECT 計數
            NEW_REJECT_COUNT=$((CURRENT_REJECT_COUNT + 1))

            # 檢查是否達到上限（5次）
            if [ $NEW_REJECT_COUNT -ge 5 ]; then
                echo ""
                echo "╔════════════════════════════════════════════════════════════════╗"
                echo "║           🚨 達到 REJECT 上限                                   ║"
                echo "╚════════════════════════════════════════════════════════════════╝"
                echo ""
                echo "⚠️ REVIEWER 已 REJECT $NEW_REJECT_COUNT 次，達到上限" >&2
                echo "🛑 狀態已設定為 'escalated'，需要人工介入" >&2
                echo "" >&2
                echo "📋 建議操作：" >&2
                echo "   1. 重新評估需求和設計" >&2
                echo "   2. 尋求資深工程師協助" >&2
                echo "   3. 考慮拆分任務" >&2
                echo "   4. 清除狀態重新開始: rm $STATE_FILE" >&2
                echo "" >&2

                RESULT="escalated"
            fi

            # E2E 統計：記錄結果
            record_e2e_result "reviewer" "reject" "$CURRENT_RISK_LEVEL" "$CHANGE_ID"

            record_state "reviewer" "$RESULT" "$CHANGE_ID" "$CURRENT_FAIL_COUNT" "$CURRENT_RISK_LEVEL" "$NEW_REJECT_COUNT"

            if [ "$RESULT" != "escalated" ]; then
                echo ""
                echo "╭─────────────────────────────────────────╮"
                echo "│ 📋 下一步: 請委派 DEVELOPER 修復       │"
                echo "╰─────────────────────────────────────────╯"
                echo "📊 REJECT 次數: $NEW_REJECT_COUNT / 5"
            fi
        else
            echo "⚠️ REVIEWER 輸出應包含明確判定"
            echo "   預期關鍵字: APPROVED / REJECT / REQUEST CHANGES"
            RESULT="unclear"

            record_state "reviewer" "$RESULT" "$CHANGE_ID" "$CURRENT_FAIL_COUNT" "$CURRENT_RISK_LEVEL" "$CURRENT_REJECT_COUNT"
        fi
        ;;

    tester)
        # 檢查是否有 PASS/FAIL
        HAS_PASS=$(echo "$OUTPUT" | grep -ci "PASS\|通過\|成功" 2>/dev/null | tr -d '\n' || echo 0)
        HAS_FAIL=$(echo "$OUTPUT" | grep -ci "FAIL\|失敗\|錯誤" 2>/dev/null | tr -d '\n' || echo 0)
        # 確保是數字
        HAS_PASS="${HAS_PASS:-0}"
        HAS_FAIL="${HAS_FAIL:-0}"
        [[ ! "$HAS_PASS" =~ ^[0-9]+$ ]] && HAS_PASS=0
        [[ ! "$HAS_FAIL" =~ ^[0-9]+$ ]] && HAS_FAIL=0

        # 獲取當前失敗次數和風險等級
        CURRENT_FAIL_COUNT=$(get_fail_count)
        CURRENT_RISK_LEVEL=$(get_risk_level)

        if [ "$HAS_PASS" -gt 0 ] && [ "$HAS_FAIL" -eq 0 ]; then
            echo "✅ TESTER PASS - 所有測試通過"
            RESULT="pass"

            # E2E 統計：記錄結果
            record_e2e_result "tester" "pass" "$CURRENT_RISK_LEVEL" "$CHANGE_ID"

            # 任務 10: 移除 HIGH RISK 人工確認
            # 所有風險等級 PASS 後直接完成
            # 成功後重置失敗計數和 REJECT 計數
            record_state "tester" "$RESULT" "$CHANGE_ID" 0 "$CURRENT_RISK_LEVEL" 0

            echo ""
            echo "╭─────────────────────────────────────────╮"
            echo "│ 🎉 任務完成！可以進行下一個任務        │"
            echo "╰─────────────────────────────────────────╯"

            # 清理狀態檔案（任務完成）
            if [ -n "$CHANGE_ID" ]; then
                rm -f "$STATE_FILE" 2>/dev/null
            fi

        elif [ "$HAS_FAIL" -gt 0 ]; then
            echo "❌ TESTER FAIL - 發現測試失敗"
            RESULT="fail"

            # 增加失敗計數
            NEW_FAIL_COUNT=$((CURRENT_FAIL_COUNT + 1))

            # E2E 統計：記錄重試
            record_e2e_retry "tester" "測試失敗" "$NEW_FAIL_COUNT"

            # 重試機制：根據風險等級決定處理方式
            # LOW: 1 次後升級為 MEDIUM
            # MEDIUM: 3 次後等待用戶介入
            # HIGH: 2 次後暫停 + 通知用戶
            NEW_RISK_LEVEL="$CURRENT_RISK_LEVEL"

            case "$CURRENT_RISK_LEVEL" in
                LOW)
                    if [ $NEW_FAIL_COUNT -ge 1 ]; then
                        NEW_RISK_LEVEL="MEDIUM"
                        echo ""
                        echo "⬆️ 風險等級升級: LOW → MEDIUM（失敗次數: $NEW_FAIL_COUNT）"
                    fi
                    ;;
                MEDIUM)
                    if [ $NEW_FAIL_COUNT -ge 3 ]; then
                        echo ""
                        echo "🛑 已達最大重試次數（3 次），等待用戶介入"
                        echo "   請手動檢查問題或決定下一步"
                    fi
                    ;;
                HIGH)
                    if [ $NEW_FAIL_COUNT -ge 2 ]; then
                        echo ""
                        echo "🛑 HIGH RISK 任務已失敗 2 次"
                        echo "   ⚠️ 暫停自動流程，需要人工審查"
                        echo "   請檢查：安全性影響、回滾計劃、是否需要專家協助"
                    fi
                    ;;
            esac

            # 保留 REJECT 計數
            CURRENT_REJECT_COUNT=$(get_reject_count)
            record_state "tester" "$RESULT" "$CHANGE_ID" "$NEW_FAIL_COUNT" "$NEW_RISK_LEVEL" "$CURRENT_REJECT_COUNT"

            echo ""
            echo "╭─────────────────────────────────────────╮"
            echo "│ 📋 下一步: 請委派 DEBUGGER 分析        │"
            echo "│    或 DEVELOPER 修復                    │"
            echo "╰─────────────────────────────────────────╯"
            echo "📊 失敗次數: $NEW_FAIL_COUNT | 風險等級: $NEW_RISK_LEVEL"
        else
            echo "⚠️ TESTER 輸出應包含 PASS 或 FAIL"
            RESULT="unclear"

            CURRENT_REJECT_COUNT=$(get_reject_count)
            record_state "tester" "$RESULT" "$CHANGE_ID" "$CURRENT_FAIL_COUNT" "$CURRENT_RISK_LEVEL" "$CURRENT_REJECT_COUNT"
        fi
        ;;

    debugger)
        # 保留現有的失敗計數、REJECT 計數和風險等級
        CURRENT_FAIL_COUNT=$(get_fail_count)
        CURRENT_REJECT_COUNT=$(get_reject_count)
        CURRENT_RISK_LEVEL=$(get_risk_level)

        # 檢查是否有修復方案
        if echo "$OUTPUT" | grep -qi "修復\|fix\|solution\|建議\|原因"; then
            echo "✅ DEBUGGER 提供修復方案"
            RESULT="analyzed"
        else
            echo "⚠️ DEBUGGER 輸出建議包含問題分析和修復建議"
            RESULT="incomplete"
        fi

        record_state "debugger" "$RESULT" "$CHANGE_ID" "$CURRENT_FAIL_COUNT" "$CURRENT_RISK_LEVEL" "$CURRENT_REJECT_COUNT"

        echo ""
        echo "╭─────────────────────────────────────────╮"
        echo "│ 📋 下一步: 請委派 DEVELOPER 實施修復    │"
        echo "╰─────────────────────────────────────────╯"
        ;;

    architect)
        # 檢查是否有架構設計
        if echo "$OUTPUT" | grep -qi "架構\|設計\|模組\|component\|structure"; then
            echo "✅ ARCHITECT 輸出格式正確"
            RESULT="complete"
        else
            echo "⚠️ ARCHITECT 輸出建議包含架構說明"
            RESULT="incomplete"
        fi

        record_state "architect" "$RESULT" "$CHANGE_ID" 0 "MEDIUM"
        ;;

    designer)
        # Designer 通常不需要特別驗證
        echo "✅ DESIGNER 完成"
        RESULT="complete"

        record_state "designer" "$RESULT" "$CHANGE_ID" 0 "MEDIUM"
        ;;

    *)
        # 其他 agent 只記錄，不特別驗證
        if [ -n "$AGENT_NAME" ]; then
            echo "📋 Agent '$AGENT_NAME' 完成"
            RESULT="complete"

            record_state "$AGENT_NAME" "$RESULT" "$CHANGE_ID" 0 "MEDIUM"
        fi
        ;;
esac

# 顯示 Change ID（如果有）
if [ -n "$CHANGE_ID" ]; then
    echo ""
    echo "📌 Change: $CHANGE_ID"
fi

exit 0
