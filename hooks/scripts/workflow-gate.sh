#!/bin/bash
# workflow-gate.sh - D→R→T 強制阻擋
# 事件: PreToolUse (Task)
# 功能: 確保程式碼變更經過 DEVELOPER → REVIEWER → TESTER
# 2025 AI Guardrails: Runtime Enforcer Pattern
# 支援: 並行任務隔離（基於 Change ID）+ 時間戳過期機制
# 支援: Bypass 機制（開發測試用）

# DEBUG: 記錄 hook 被呼叫
echo "[$(date)] workflow-gate.sh called" >> /tmp/claude-workflow-debug.log

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

# 記錄 E2E 違規事件
record_e2e_violation() {
    local agent="$1"
    local reason="$2"
    local risk_level="${3:-MEDIUM}"
    local change_id="${4:-}"

    local stats_file=$(get_e2e_stats_file)
    [ -z "$stats_file" ] && return  # 非 E2E 模式，跳過

    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local json="{\"type\":\"violation\",\"timestamp\":\"$timestamp\",\"agent\":\"$agent\",\"reason\":\"$reason\",\"risk_level\":\"$risk_level\",\"fixed\":false,\"fix_iteration\":0"

    if [ -n "$change_id" ]; then
        json="$json,\"change_id\":\"$change_id\""
    fi

    json="$json}"

    echo "$json" >> "$stats_file"
    echo "[$(date)] E2E VIOLATION: $agent - $reason" >> /tmp/claude-workflow-debug.log
}

# 記錄 E2E 合規事件
record_e2e_compliance() {
    local agent="$1"
    local risk_level="${2:-MEDIUM}"
    local change_id="${3:-}"

    local stats_file=$(get_e2e_stats_file)
    [ -z "$stats_file" ] && return  # 非 E2E 模式，跳過

    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local json="{\"type\":\"compliance\",\"timestamp\":\"$timestamp\",\"agent\":\"$agent\",\"risk_level\":\"$risk_level\""

    if [ -n "$change_id" ]; then
        json="$json,\"change_id\":\"$change_id\""
    fi

    json="$json}"

    echo "$json" >> "$stats_file"
}

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

# ═══════════════════════════════════════════════════════════════
# 風險等級判定系統
# ═══════════════════════════════════════════════════════════════

# LOW: 純文檔（允許 D→T 快速通道）
readonly LOW_RISK_EXTENSIONS="md|txt|rst|adoc"

# HIGH: 敏感路徑（業務 + CI/CD）
readonly HIGH_RISK_PATHS="auth|security|payment|api|migration|schema|secrets|\.github/workflows|\.gitlab|\.circleci|\.azure-pipelines"

# HIGH: 敏感檔案類型（容器 + 資料庫 + CI/CD）
readonly HIGH_RISK_FILES="Dockerfile|docker-compose|\.env|\.sql|\.prisma|gitlab-ci\.yml|azure-pipelines\.yml|bitbucket-pipelines\.yml|Jenkinsfile|\.travis\.yml|cloudbuild\.yaml"

# HIGH: 敏感關鍵字
readonly HIGH_RISK_KEYWORDS="password|token|secret|credential|private\.key|api\.key|aws_access|ssh\.key"

# 多檔案閾值（超過此數量 → HIGH）
readonly FILE_COUNT_THRESHOLD=5

# 風險等級判定函數
# 參數: $1 = prompt 內容
# 返回: LOW, MEDIUM, HIGH
detect_risk_level() {
    local content="$1"

    # Step 1: 檢查 HIGH RISK（優先）
    # 1a. 敏感路徑
    if echo "$content" | grep -qiE "/($HIGH_RISK_PATHS)/"; then
        echo "HIGH"
        return
    fi

    # 1b. 敏感檔案類型
    if echo "$content" | grep -qiE "($HIGH_RISK_FILES)"; then
        echo "HIGH"
        return
    fi

    # 1c. 敏感關鍵字
    if echo "$content" | grep -qiE "($HIGH_RISK_KEYWORDS)"; then
        echo "HIGH"
        return
    fi

    # Step 2: 提取檔案路徑並計數
    local files=$(echo "$content" | grep -oE '[a-zA-Z0-9_./-]+\.[a-zA-Z0-9]+' | sort -u)
    local file_count=0
    if [ -n "$files" ]; then
        file_count=$(echo "$files" | wc -l | tr -d ' ')
    fi

    # 2a. 多檔案變更 → HIGH RISK
    if [ "$file_count" -gt "$FILE_COUNT_THRESHOLD" ]; then
        echo "HIGH"
        return
    fi

    # Step 3: 無檔案可判定 → MEDIUM
    if [ -z "$files" ] || [ "$file_count" -eq 0 ]; then
        echo "MEDIUM"
        return
    fi

    # Step 4: 檢查是否全部為 LOW 風險檔案
    local has_non_low=false
    for file in $files; do
        local ext=$(echo "$file" | sed 's/.*\.//')
        if ! echo "$ext" | grep -qiE "^($LOW_RISK_EXTENSIONS)$"; then
            has_non_low=true
            break
        fi
    done

    if [ "$has_non_low" = false ]; then
        echo "LOW"
    else
        echo "MEDIUM"
    fi
}

# ═══════════════════════════════════════════════════════════════

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
FAIL_COUNT=0
STORED_RISK_LEVEL="MEDIUM"
STATE_VALID=false

if [ -f "$STATE_FILE" ]; then
    LAST_AGENT=$(jq -r '.agent // empty' "$STATE_FILE" 2>/dev/null)
    LAST_RESULT=$(jq -r '.result // empty' "$STATE_FILE" 2>/dev/null)
    LAST_TIMESTAMP=$(jq -r '.timestamp // empty' "$STATE_FILE" 2>/dev/null)
    FAIL_COUNT=$(jq -r '.fail_count // 0' "$STATE_FILE" 2>/dev/null)
    STORED_RISK_LEVEL=$(jq -r '.risk_level // "MEDIUM"' "$STATE_FILE" 2>/dev/null)

    # 確保 FAIL_COUNT 是數字
    if ! [[ "$FAIL_COUNT" =~ ^[0-9]+$ ]]; then
        FAIL_COUNT=0
    fi

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

# 重試閾值常數
readonly MAX_RETRY_LOW=1
readonly MAX_RETRY_MEDIUM=3
readonly MAX_RETRY_HIGH=2

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
        # E2E 統計：記錄合規
        record_e2e_compliance "developer" "MEDIUM" "$CHANGE_ID"

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
        # E2E 統計：記錄合規
        record_e2e_compliance "reviewer" "MEDIUM" "$CHANGE_ID"

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
        # 例外：LOW 風險允許 D→T 快速通道

        # 判定風險等級
        DETECTED_RISK_LEVEL=$(detect_risk_level "$PROMPT")

        # 只有當有失敗記錄時，才考慮存儲的風險等級（可能已升級）
        if [ "$FAIL_COUNT" -gt 0 ]; then
            # 有失敗歷史：取較高的風險等級
            if [ "$STORED_RISK_LEVEL" = "HIGH" ]; then
                RISK_LEVEL="HIGH"
            elif [ "$STORED_RISK_LEVEL" = "MEDIUM" ] && [ "$DETECTED_RISK_LEVEL" != "HIGH" ]; then
                RISK_LEVEL="MEDIUM"
            else
                RISK_LEVEL="$DETECTED_RISK_LEVEL"
            fi
        else
            # 無失敗歷史：使用檢測到的風險等級
            RISK_LEVEL="$DETECTED_RISK_LEVEL"
        fi

        # 檢查是否超過重試閾值
        RETRY_BLOCKED=false
        case "$RISK_LEVEL" in
            LOW)
                if [ "$FAIL_COUNT" -ge "$MAX_RETRY_LOW" ]; then
                    RETRY_BLOCKED=true
                    RETRY_MSG="LOW RISK 已失敗 $FAIL_COUNT 次（閾值: $MAX_RETRY_LOW），已升級為 MEDIUM"
                fi
                ;;
            MEDIUM)
                if [ "$FAIL_COUNT" -ge "$MAX_RETRY_MEDIUM" ]; then
                    RETRY_BLOCKED=true
                    RETRY_MSG="MEDIUM RISK 已失敗 $FAIL_COUNT 次（閾值: $MAX_RETRY_MEDIUM），需要用戶介入"
                fi
                ;;
            HIGH)
                if [ "$FAIL_COUNT" -ge "$MAX_RETRY_HIGH" ]; then
                    RETRY_BLOCKED=true
                    RETRY_MSG="HIGH RISK 已失敗 $FAIL_COUNT 次（閾值: $MAX_RETRY_HIGH），暫停自動流程"
                fi
                ;;
        esac

        # 如果超過重試閾值，阻擋
        if [ "$RETRY_BLOCKED" = true ]; then
            # E2E 統計：記錄違規
            record_e2e_violation "tester" "超過重試閾值: $RETRY_MSG" "$RISK_LEVEL" "$CHANGE_ID"

            echo "" >&2
            echo "╔════════════════════════════════════════════════════════════════╗" >&2
            echo "║               🛑 超過重試閾值                                   ║" >&2
            echo "╚════════════════════════════════════════════════════════════════╝" >&2
            echo "" >&2
            echo "⚠️ $RETRY_MSG" >&2
            echo "" >&2
            echo "📋 建議操作：" >&2
            echo "   1. 手動檢查失敗原因" >&2
            echo "   2. 考慮是否需要重新設計" >&2
            echo "   3. 清除狀態後重新開始: rm $STATE_FILE" >&2
            echo "" >&2
            echo "{\"decision\":\"block\",\"reason\":\"超過重試閾值: $RETRY_MSG\"}"
            exit 0
        fi

        # 阻擋條件：上一個是 DEVELOPER（跳過審查）且狀態有效
        if [ "$STATE_VALID" = true ] && [ "$LAST_AGENT" = "developer" ]; then
            # LOW 風險例外：允許 D→T 快速通道
            if [ "$RISK_LEVEL" = "LOW" ]; then
                # E2E 統計：記錄合規（LOW 風險快速通道）
                record_e2e_compliance "tester" "LOW" "$CHANGE_ID"

                echo "" >&2
                echo "╔════════════════════════════════════════════════════════════════╗" >&2
                echo "║               🧪 TESTER 啟動（LOW 風險快速通道）                 ║" >&2
                echo "╚════════════════════════════════════════════════════════════════╝" >&2
                echo "🟢 風險等級: LOW（純文檔變更）" >&2
                echo "⚡ D→T 快速通道：允許跳過 REVIEWER" >&2
                echo "📚 Skills: drt-rules, test, error-handling" >&2
                echo "🧰 工具：Read, Glob, Grep, Bash" >&2
                echo "" >&2
            else
                # MEDIUM/HIGH 風險：阻擋
                # E2E 統計：記錄違規
                record_e2e_violation "tester" "跳過 REVIEWER 審查" "$RISK_LEVEL" "$CHANGE_ID"

                echo "╔════════════════════════════════════════════════════════════════╗" >&2
                echo "║                   ❌ 流程違規                                   ║" >&2
                echo "╚════════════════════════════════════════════════════════════════╝" >&2
                echo "" >&2
                if [ "$RISK_LEVEL" = "HIGH" ]; then
                    echo "🔴 風險等級: HIGH" >&2
                else
                    echo "🟡 風險等級: MEDIUM" >&2
                fi
                echo "🚫 不允許跳過 REVIEWER 直接進行測試" >&2
                echo "" >&2
                echo "📋 正確流程:" >&2
                echo "   DEVELOPER → REVIEWER → TESTER" >&2
                echo "       ↓           ↓" >&2
                echo "    實作完成    APPROVE 後才能測試" >&2
                echo "" >&2
                echo "💡 請先委派 REVIEWER 審查程式碼" >&2
                # JSON decision 輸出到 stdout（Claude Code 解析）
                echo "{\"decision\":\"block\",\"reason\":\"跳過 REVIEWER 審查，違反 D→R→T 流程（風險等級: $RISK_LEVEL）\"}"
                exit 0
            fi
        else
            # 正常流程：REVIEWER → TESTER
            # E2E 統計：記錄合規
            record_e2e_compliance "tester" "$RISK_LEVEL" "$CHANGE_ID"

            echo "" >&2
            echo "╔════════════════════════════════════════════════════════════════╗" >&2
            echo "║                    🧪 TESTER 啟動                               ║" >&2
            echo "╚════════════════════════════════════════════════════════════════╝" >&2
            if [ "$STATE_VALID" = false ]; then
                echo "⚠️ 注意：無法驗證流程狀態（可能已過期）" >&2
            elif [ "$LAST_AGENT" = "reviewer" ] && [ "$LAST_RESULT" != "approve" ]; then
                echo "⚠️ REVIEWER 結果為 '$LAST_RESULT'，非 APPROVE" >&2
            fi
            # 顯示風險等級
            case "$RISK_LEVEL" in
                LOW)  echo "🟢 風險等級: LOW" >&2 ;;
                HIGH) echo "🔴 風險等級: HIGH" >&2 ;;
                *)    echo "🟡 風險等級: MEDIUM" >&2 ;;
            esac
            # 顯示失敗次數（如果有）
            if [ "$FAIL_COUNT" -gt 0 ]; then
                echo "📊 失敗次數: $FAIL_COUNT" >&2
            fi
            echo "📚 Skills: drt-rules, test, error-handling" >&2
            echo "🧰 工具：Read, Glob, Grep, Bash" >&2
            echo "" >&2
        fi
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
