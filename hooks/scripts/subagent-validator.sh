#!/bin/bash
# subagent-validator.sh - 驗證 Agent 輸出 + 記錄狀態
# 事件: SubagentStop
# 功能: 確保 Agent 輸出符合預期格式，並記錄狀態供流程控制
# 2025 AI Guardrails: Post-hook Validation + State Management
# 支援: 並行任務隔離（基於 Change ID）

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)

# 狀態目錄
STATE_DIR="${PWD}/.claude"
mkdir -p "$STATE_DIR" 2>/dev/null

# 解析輸出
AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // empty' | tr '[:upper:]' '[:lower:]')
OUTPUT=$(echo "$INPUT" | jq -r '.output // empty')
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

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

# 決定狀態檔案路徑
if [ -n "$CHANGE_ID" ]; then
    STATE_FILE="${STATE_DIR}/.drt-state-${CHANGE_ID}"
else
    STATE_FILE="${STATE_DIR}/.drt-workflow-state"
fi

# 初始化結果
RESULT="unknown"

# 輔助函數：記錄狀態
record_state() {
    local agent=$1
    local result=$2
    local change_id=$3

    local json="{\"agent\":\"$agent\",\"result\":\"$result\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    if [ -n "$change_id" ]; then
        json="$json,\"change_id\":\"$change_id\""
    fi
    json="$json}"

    echo "$json" > "$STATE_FILE"
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

        # 記錄狀態
        record_state "developer" "$RESULT" "$CHANGE_ID"

        echo ""
        echo "╭─────────────────────────────────────────╮"
        echo "│ 📋 下一步: 請委派 REVIEWER 審查         │"
        echo "╰─────────────────────────────────────────╯"
        ;;

    reviewer)
        # 檢查是否有 Verdict
        if echo "$OUTPUT" | grep -qi "APPROVED\|APPROVE\|通過\|批准"; then
            echo "✅ REVIEWER APPROVED"
            RESULT="approve"

            record_state "reviewer" "$RESULT" "$CHANGE_ID"

            echo ""
            echo "╭─────────────────────────────────────────╮"
            echo "│ 📋 下一步: 請委派 TESTER 測試          │"
            echo "╰─────────────────────────────────────────╯"

        elif echo "$OUTPUT" | grep -qi "REJECT\|REQUEST CHANGES\|需要修改\|駁回"; then
            echo "🔄 REVIEWER REQUEST CHANGES"
            RESULT="reject"

            record_state "reviewer" "$RESULT" "$CHANGE_ID"

            echo ""
            echo "╭─────────────────────────────────────────╮"
            echo "│ 📋 下一步: 請委派 DEVELOPER 修復       │"
            echo "╰─────────────────────────────────────────╯"
        else
            echo "⚠️ REVIEWER 輸出應包含明確判定"
            echo "   預期關鍵字: APPROVED / REJECT / REQUEST CHANGES"
            RESULT="unclear"

            record_state "reviewer" "$RESULT" "$CHANGE_ID"
        fi
        ;;

    tester)
        # 檢查是否有 PASS/FAIL
        HAS_PASS=$(echo "$OUTPUT" | grep -ci "PASS\|通過\|成功" || echo 0)
        HAS_FAIL=$(echo "$OUTPUT" | grep -ci "FAIL\|失敗\|錯誤" || echo 0)

        if [ "$HAS_PASS" -gt 0 ] && [ "$HAS_FAIL" -eq 0 ]; then
            echo "✅ TESTER PASS - 所有測試通過"
            RESULT="pass"

            record_state "tester" "$RESULT" "$CHANGE_ID"

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

            record_state "tester" "$RESULT" "$CHANGE_ID"

            echo ""
            echo "╭─────────────────────────────────────────╮"
            echo "│ 📋 下一步: 請委派 DEBUGGER 分析        │"
            echo "│    或 DEVELOPER 修復                    │"
            echo "╰─────────────────────────────────────────╯"
        else
            echo "⚠️ TESTER 輸出應包含 PASS 或 FAIL"
            RESULT="unclear"

            record_state "tester" "$RESULT" "$CHANGE_ID"
        fi
        ;;

    debugger)
        # 檢查是否有修復方案
        if echo "$OUTPUT" | grep -qi "修復\|fix\|solution\|建議\|原因"; then
            echo "✅ DEBUGGER 提供修復方案"
            RESULT="analyzed"
        else
            echo "⚠️ DEBUGGER 輸出建議包含問題分析和修復建議"
            RESULT="incomplete"
        fi

        record_state "debugger" "$RESULT" "$CHANGE_ID"

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

        record_state "architect" "$RESULT" "$CHANGE_ID"
        ;;

    designer)
        # Designer 通常不需要特別驗證
        echo "✅ DESIGNER 完成"
        RESULT="complete"

        record_state "designer" "$RESULT" "$CHANGE_ID"
        ;;

    *)
        # 其他 agent 只記錄，不特別驗證
        if [ -n "$AGENT_NAME" ]; then
            echo "📋 Agent '$AGENT_NAME' 完成"
            RESULT="complete"

            record_state "$AGENT_NAME" "$RESULT" "$CHANGE_ID"
        fi
        ;;
esac

# 顯示 Change ID（如果有）
if [ -n "$CHANGE_ID" ]; then
    echo ""
    echo "📌 Change: $CHANGE_ID"
fi

exit 0
