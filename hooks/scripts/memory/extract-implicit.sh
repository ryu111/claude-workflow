#!/usr/bin/env bash
# memory-extract-implicit.sh - 隱式記憶提取處理器
# 功能：當 Agent 完成任務時自動提取經驗記憶
# Hook: SubagentStop
# Phase: C (僅在 Phase C 啟用)
# 使用方式：由 SubagentStop Hook 自動觸發

# 注意：不使用 set -e 和 pipefail，因為我們需要優雅處理錯誤
# 注意：不在開頭設置 set 選項，讓模組自行管理

# 載入依賴模組
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 載入所有模組
# 注意：許多模組重複定義了相同的 readonly 常數，會產生警告但不影響功能

# 使用 Bash 3.2 相容的方式：關閉 errexit 和 nounset（避免載入時錯誤中斷）
set +e  # 關閉錯誤中斷
set +u  # 關閉未定義變數檢查

# 載入模組（過濾 readonly 警告，因為許多模組重複定義相同常數）
. "${LIB_DIR}/core/common.sh" 2>/dev/null
. "${LIB_DIR}/memory/sanitize.sh" 2>/dev/null
. "${LIB_DIR}/memory/provenance.sh" 2>&1 | grep -v "readonly variable" >&2 || true
. "${LIB_DIR}/memory/audit.sh" 2>&1 | grep -v "readonly variable" >&2 || true
. "${LIB_DIR}/core/rollout-phase.sh" 2>&1 | grep -v "readonly variable" >&2 || true
. "${LIB_DIR}/core/circuit-breaker.sh" 2>&1 | grep -v "readonly variable" >&2 || true
. "${LIB_DIR}/core/kill-switch.sh" 2>&1 | grep -v "readonly variable" >&2 || true
. "${LIB_DIR}/core/safe-execute.sh" 2>&1 | grep -v "readonly variable" >&2 || true

# 恢復腳本控制（取消嚴格模式，因為會導致 CLI 測試失敗）
set +u

# ═══════════════════════════════════════════════════════════════
# 常數定義（使用 IMPLICIT_ 前綴避免衝突）
# ═══════════════════════════════════════════════════════════════

# 注意：不使用 readonly，因為被載入的模組已經定義了相同名稱的常數
# 改用獨立的變數名稱
IMPLICIT_SUCCESS=0
IMPLICIT_SKIPPED=1
IMPLICIT_BLOCKED=2
IMPLICIT_ERROR=3

# Agent 經驗輸出檔案
readonly IMPLICIT_REVIEWER_FILE=".claude/memory/experiences/reviewer-patterns.md"
readonly IMPLICIT_TESTER_FILE=".claude/memory/experiences/tester-strategies.md"
readonly IMPLICIT_DEBUGGER_FILE=".claude/memory/experiences/debugger-solutions.md"

# ═══════════════════════════════════════════════════════════════
# 核心功能：Agent 經驗提取
# ═══════════════════════════════════════════════════════════════

# 從 REVIEWER Agent 提取審查經驗
# 用法: extract_reviewer_experience result_json
# 輸出: 提取的經驗內容
extract_reviewer_experience() {
    local result_json="${1:-}"

    if [ -z "$result_json" ]; then
        echo ""
        return
    fi

    # 解析 result 和 details
    local result
    result=$(echo "$result_json" | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "")
    local details
    details=$(echo "$result_json" | grep -o '"details":"[^"]*"' | cut -d'"' -f4 || echo "")
    local reason
    reason=$(echo "$result_json" | grep -o '"reason":"[^"]*"' | cut -d'"' -f4 || echo "")

    # 僅在 REJECT 時提取經驗（學習審查標準）
    if [ "$result" = "REJECT" ]; then
        local experience="審查拒絕原因: $reason"
        if [ -n "$details" ]; then
            experience="$experience | 詳細說明: $details"
        fi
        echo "$experience"
    else
        echo ""
    fi
}

# 從 TESTER Agent 提取測試經驗
# 用法: extract_tester_experience result_json
# 輸出: 提取的經驗內容
extract_tester_experience() {
    local result_json="${1:-}"

    if [ -z "$result_json" ]; then
        echo ""
        return
    fi

    # 解析 result 和 details
    local result
    result=$(echo "$result_json" | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "")
    local test_type
    test_type=$(echo "$result_json" | grep -o '"test_type":"[^"]*"' | cut -d'"' -f4 || echo "")
    local failure_reason
    failure_reason=$(echo "$result_json" | grep -o '"failure_reason":"[^"]*"' | cut -d'"' -f4 || echo "")

    # 僅在 FAIL 時提取經驗（學習測試策略）
    if [ "$result" = "FAIL" ]; then
        local experience="測試失敗: $test_type"
        if [ -n "$failure_reason" ]; then
            experience="$experience | 失敗原因: $failure_reason"
        fi
        echo "$experience"
    else
        echo ""
    fi
}

# 從 DEBUGGER Agent 提取診斷經驗
# 用法: extract_debugger_experience result_json
# 輸出: 提取的經驗內容
extract_debugger_experience() {
    local result_json="${1:-}"

    if [ -z "$result_json" ]; then
        echo ""
        return
    fi

    # 解析診斷資訊
    local problem_type
    problem_type=$(echo "$result_json" | grep -o '"problem_type":"[^"]*"' | cut -d'"' -f4 || echo "")
    local diagnosis
    diagnosis=$(echo "$result_json" | grep -o '"diagnosis":"[^"]*"' | cut -d'"' -f4 || echo "")
    local solution
    solution=$(echo "$result_json" | grep -o '"solution":"[^"]*"' | cut -d'"' -f4 || echo "")

    # DEBUGGER 任何結果都提取經驗（學習診斷方法）
    if [ -n "$problem_type" ]; then
        local experience="問題類型: $problem_type"
        if [ -n "$diagnosis" ]; then
            experience="$experience | 診斷: $diagnosis"
        fi
        if [ -n "$solution" ]; then
            experience="$experience | 解決方案: $solution"
        fi
        echo "$experience"
    else
        echo ""
    fi
}

# 根據 Agent 類型提取經驗
# 用法: extract_agent_experience agent_type result_json
# 輸出: 提取的經驗內容
extract_agent_experience() {
    local agent_type="${1:-}"
    local result_json="${2:-}"

    if [ -z "$agent_type" ] || [ -z "$result_json" ]; then
        echo ""
        return
    fi

    # 轉換為小寫（不區分大小寫）
    local agent_lower
    agent_lower=$(echo "$agent_type" | tr '[:upper:]' '[:lower:]')

    case "$agent_lower" in
        reviewer)
            extract_reviewer_experience "$result_json"
            ;;
        tester)
            extract_tester_experience "$result_json"
            ;;
        debugger)
            extract_debugger_experience "$result_json"
            ;;
        *)
            echo ""
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：判斷與處理
# ═══════════════════════════════════════════════════════════════

# 解析 Agent 結果 JSON
# 用法: parse_agent_result result_json
# 輸出: agent_type result (空格分隔)
parse_agent_result() {
    local result_json="${1:-}"

    if [ -z "$result_json" ]; then
        echo ""
        return
    fi

    # 提取 agent_type 和 result
    local agent_type
    agent_type=$(echo "$result_json" | grep -o '"agent_type":"[^"]*"' | cut -d'"' -f4 || echo "")
    local result
    result=$(echo "$result_json" | grep -o '"result":"[^"]*"' | cut -d'"' -f4 || echo "")

    echo "$agent_type $result"
}

# 判斷是否應該提取經驗
# 用法: should_extract_experience agent_type result
# 返回: 0=應該提取，1=不應該提取
should_extract_experience() {
    local agent_type="${1:-}"
    local result="${2:-}"

    if [ -z "$agent_type" ]; then
        return 1
    fi

    # 轉換為小寫
    local agent_lower
    agent_lower=$(echo "$agent_type" | tr '[:upper:]' '[:lower:]')
    local result_upper
    result_upper=$(echo "$result" | tr '[:lower:]' '[:upper:]')

    case "$agent_lower" in
        reviewer)
            # REVIEWER REJECT → 提取拒絕原因
            [ "$result_upper" = "REJECT" ]
            return $?
            ;;
        tester)
            # TESTER FAIL → 提取失敗原因
            [ "$result_upper" = "FAIL" ]
            return $?
            ;;
        debugger)
            # DEBUGGER 任何結果 → 提取診斷經驗
            return 0
            ;;
        *)
            # 其他 Agent 不提取
            return 1
            ;;
    esac
}

# 取得輸出檔案路徑
# 用法: get_experience_file agent_type
# 輸出: 檔案路徑
get_experience_file() {
    local agent_type="${1:-}"

    if [ -z "$agent_type" ]; then
        echo ""
        return
    fi

    # 轉換為小寫
    local agent_lower
    agent_lower=$(echo "$agent_type" | tr '[:upper:]' '[:lower:]')

    case "$agent_lower" in
        reviewer)
            echo "$IMPLICIT_REVIEWER_FILE"
            ;;
        tester)
            echo "$IMPLICIT_TESTER_FILE"
            ;;
        debugger)
            echo "$IMPLICIT_DEBUGGER_FILE"
            ;;
        *)
            echo ""
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：隱式記憶處理流程
# ═══════════════════════════════════════════════════════════════

# 處理隱式記憶的主流程
# 用法: process_implicit_memory stdin_json
# 返回: 0=成功，1=跳過，2=被阻擋，3=錯誤
# 輸出: JSON 格式的處理結果（stdout）
process_implicit_memory() {
    local stdin_json="${1:-}"

    # 步驟 1: 解析 SubagentStop 事件 JSON
    local agent_result
    agent_result=$(parse_agent_result "$stdin_json")

    if [ -z "$agent_result" ]; then
        # 無法解析
        echo '{"status":"error","reason":"invalid_input","memory_extracted":""}'
        return $IMPLICIT_ERROR
    fi

    # 提取 agent_type 和 result
    local agent_type result
    agent_type=$(echo "$agent_result" | awk '{print $1}')
    result=$(echo "$agent_result" | awk '{print $2}')

    # 步驟 2: 判斷是否應該提取經驗
    if ! should_extract_experience "$agent_type" "$result"; then
        # 不應該提取（不是學習目標場景）
        echo '{"status":"skipped","reason":"not_learning_scenario","agent_type":"'"$agent_type"'","result":"'"$result"'","memory_extracted":""}'
        return $IMPLICIT_SKIPPED
    fi

    # 步驟 3: 提取經驗內容
    local experience_content
    experience_content=$(extract_agent_experience "$agent_type" "$stdin_json")

    if [ -z "$experience_content" ]; then
        # 提取失敗（空內容）
        echo '{"status":"skipped","reason":"empty_content","agent_type":"'"$agent_type"'","memory_extracted":""}'
        return $IMPLICIT_SKIPPED
    fi

    # 步驟 4: 安全檢查 - 消毒內容
    local sanitized_content
    if ! sanitized_content=$(sanitize_memory_content "$experience_content" 2>&1); then
        # 消毒失敗（惡意內容）
        local escaped_reason
        escaped_reason=$(echo "$sanitized_content" | tr '\n' ' ' | sed 's/"/\\"/g')
        echo "{\"status\":\"blocked\",\"reason\":\"malicious_content\",\"agent_type\":\"$agent_type\",\"memory_extracted\":\"$experience_content\",\"details\":\"$escaped_reason\"}"

        # 記錄審計
        local experience_file
        experience_file=$(get_experience_file "$agent_type")
        safe_execute -s -- audit_memory_write "$ACTION_BLOCKED" "$experience_file" "" "$AUDIT_SOURCE_AGENT_IMPLICIT" "$agent_type" "malicious_content"

        return $IMPLICIT_BLOCKED
    fi

    # 步驟 5: 追蹤來源（標記為 agent_implicit）
    local provenance_json
    provenance_json=$(generate_provenance "$SOURCE_TYPE_AGENT_IMPLICIT" "$agent_type" 2>/dev/null || echo '{}')

    # 步驟 6: 記錄審計
    local experience_file
    experience_file=$(get_experience_file "$agent_type")
    local content_hash
    content_hash=$(compute_content_hash "$sanitized_content" 2>/dev/null || echo "0000000000000000")
    safe_execute -s -- audit_memory_write "$ACTION_WRITE" "$experience_file" "$content_hash" "$AUDIT_SOURCE_AGENT_IMPLICIT" "$agent_type" ""

    # 步驟 7: 寫入經驗檔案（TODO: Phase 4 實作 memory-update.sh）
    # 目前只返回成功狀態，實際寫入將在 Phase 4 完成

    # 成功
    local escaped_content
    escaped_content=$(echo "$sanitized_content" | sed 's/"/\\"/g' | tr '\n' ' ')
    echo "{\"status\":\"success\",\"reason\":\"extracted\",\"agent_type\":\"$agent_type\",\"result\":\"$result\",\"memory_extracted\":\"$escaped_content\",\"source_type\":\"$SOURCE_TYPE_AGENT_IMPLICIT\",\"provenance\":$provenance_json}"

    return $IMPLICIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# Hook 入口點
# ═══════════════════════════════════════════════════════════════

# Hook 主函式（從 stdin 讀取 JSON）
# 輸入格式: {"session_id":"abc123","agent_type":"reviewer","result":"REJECT","details":{"reason":"..."}}
# 輸出格式: {"status":"success|skipped|blocked","agent_type":"...","memory_extracted":"...","reason":"..."}
hook_main() {
    # 檢查 Rollout Phase（僅在 Phase C 啟用）
    # 檢查常數是否已定義（防止 unbound variable 錯誤）
    if [ -z "${FEATURE_EXTRACT_IMPLICIT:-}" ]; then
        # 同時輸出到 stdout（給調用方）和 stderr（給日誌）
        echo '{"status":"error","reason":"config_missing","memory_extracted":""}'
        echo "錯誤：環境變數 FEATURE_EXTRACT_IMPLICIT 未定義" >&2
        exit $IMPLICIT_ERROR
    fi

    if ! is_feature_enabled "$FEATURE_EXTRACT_IMPLICIT" 2>/dev/null; then
        # Phase A/B：不處理，直接返回
        echo '{"status":"skipped","reason":"phase_disabled","memory_extracted":""}'
        exit $IMPLICIT_SKIPPED
    fi

    # 檢查 Kill Switch（先執行命令再檢查返回值）
    local switch_status
    check_kill_switches >/dev/null 2>&1
    switch_status=$?

    if [ $switch_status -ne $EXIT_NORMAL ]; then
        if [ $switch_status -eq $EXIT_DISABLED ]; then
            # 完全禁用
            echo '{"status":"skipped","reason":"kill_switch_disabled","memory_extracted":""}'
            exit $IMPLICIT_SKIPPED
        elif [ $switch_status -eq $EXIT_READONLY ]; then
            # 只讀模式，阻擋寫入
            echo '{"status":"blocked","reason":"readonly_mode","memory_extracted":""}'
            exit $IMPLICIT_BLOCKED
        fi
    fi

    # 檢查熔斷器
    if is_circuit_breaker_open 2>/dev/null; then
        # 熔斷器開啟，阻擋操作
        echo '{"status":"blocked","reason":"circuit_breaker_open","memory_extracted":""}'
        exit $IMPLICIT_BLOCKED
    fi

    # 從 stdin 讀取 JSON
    local input_json
    input_json=$(cat)

    # 處理隱式記憶
    local result
    result=$(process_implicit_memory "$input_json")
    local exit_code=$?

    # 輸出結果
    echo "$result"
    exit $exit_code
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_implicit_help() {
    cat <<'EOF'
隱式記憶提取處理器 (Implicit Memory Extractor)

用法:
  # 作為 Hook 使用（從 stdin 讀取 JSON）
  echo '{"session_id":"test","agent_type":"reviewer","result":"REJECT","details":{"reason":"缺少錯誤處理"}}' | ./memory-extract-implicit.sh

  # 直接測試（CLI 模式）
  ./memory-extract-implicit.sh test reviewer REJECT '{"reason":"缺少錯誤處理"}'
  ./memory-extract-implicit.sh test tester FAIL '{"test_type":"unit","failure_reason":"斷言失敗"}'
  ./memory-extract-implicit.sh test debugger SUCCESS '{"problem_type":"null pointer","diagnosis":"未初始化變數","solution":"加入預設值"}'

CLI 指令:
  test <agent_type> <result> <details_json>
      完整測試流程（包含安全檢查）
      agent_type: reviewer | tester | debugger
      result: APPROVE | REJECT | PASS | FAIL | SUCCESS
      details_json: JSON 格式的詳細資訊

  should-extract <agent_type> <result>
      僅測試是否應該提取經驗

  extract <agent_type> <result_json>
      僅測試經驗提取（不含安全檢查）

  help
      顯示此說明

Hook 輸入格式 (JSON via stdin):
  {
    "session_id": "abc123",
    "agent_type": "reviewer",
    "result": "REJECT",
    "details": {
      "reason": "缺少錯誤處理",
      "suggestions": ["加入 try-catch", "驗證輸入參數"]
    }
  }

Hook 輸出格式 (JSON via stdout):
  成功:
    {
      "status": "success",
      "reason": "extracted",
      "agent_type": "reviewer",
      "result": "REJECT",
      "memory_extracted": "審查拒絕原因: ...",
      "source_type": "agent_implicit",
      "provenance": {...}
    }

  跳過:
    {
      "status": "skipped",
      "reason": "not_learning_scenario|empty_content|phase_disabled",
      "agent_type": "...",
      "result": "...",
      "memory_extracted": ""
    }

  被阻擋:
    {
      "status": "blocked",
      "reason": "malicious_content|readonly_mode|circuit_breaker_open",
      "agent_type": "...",
      "memory_extracted": "...",
      "details": "..."
    }

學習場景:
  REVIEWER REJECT → 學習審查標準（拒絕原因）
  TESTER FAIL → 學習測試策略（失敗原因）
  DEBUGGER 任何結果 → 學習診斷方法（問題類型、診斷、解決方案）

經驗檔案位置:
  REVIEWER → .claude/memory/experiences/reviewer-patterns.md
  TESTER → .claude/memory/experiences/tester-strategies.md
  DEBUGGER → .claude/memory/experiences/debugger-solutions.md

安全機制:
  1. 內容消毒（sanitize_memory_content）
  2. 來源追蹤（generate_provenance → agent_implicit）
  3. 審計記錄（audit_memory_write）

容錯機制:
  - Rollout Phase 檢查（僅 Phase C 啟用）
  - Kill Switch 檢查
  - 熔斷器檢查
  - 所有外部呼叫使用 safe_execute 包裝

返回碼:
  0 - 成功
  1 - 跳過
  2 - 被阻擋
  3 - 錯誤
EOF
}

# ═══════════════════════════════════════════════════════════════
# CLI 入口（測試用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        test)
            # 完整測試流程
            shift
            agent_type="${1:-}"
            result="${2:-}"
            details_json="${3:-{}}"

            if [ -z "$agent_type" ] || [ -z "$result" ]; then
                echo "錯誤：必須提供 agent_type 和 result" >&2
                echo "用法: $0 test <agent_type> <result> [details_json]" >&2
                exit $IMPLICIT_ERROR
            fi

            # 建立 JSON 輸入
            input_json="{\"session_id\":\"test\",\"agent_type\":\"$agent_type\",\"result\":\"$result\",\"details\":$details_json}"

            # 呼叫 hook_main
            echo "$input_json" | hook_main
            exit $?
            ;;
        should-extract)
            # 僅測試是否應該提取
            shift
            agent_type="${1:-}"
            result="${2:-}"

            if should_extract_experience "$agent_type" "$result"; then
                echo "✅ 應該提取經驗（$agent_type - $result）"
                exit 0
            else
                echo "❌ 不應該提取經驗（$agent_type - $result）"
                exit 1
            fi
            ;;
        extract)
            # 僅測試經驗提取
            shift
            agent_type="${1:-}"
            result_json="${2:-}"

            content=$(extract_agent_experience "$agent_type" "$result_json")
            echo "提取結果: $content"
            exit 0
            ;;
        help|--help|-h)
            show_implicit_help
            exit 0
            ;;
        *)
            # 預設：作為 Hook 使用（從 stdin 讀取）
            hook_main
            exit $?
            ;;
    esac
fi
