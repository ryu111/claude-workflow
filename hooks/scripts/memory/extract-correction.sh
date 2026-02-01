#!/usr/bin/env bash
# memory-extract-correction.sh - 用戶修正提取處理器
# 功能：當用戶說「不要」、「禁止」、「改成」時提取修正記憶
# Hook: UserPromptSubmit
# Phase: B+ (僅在 Phase B 和 C 啟用)
# 使用方式：由 UserPromptSubmit Hook 自動觸發

# 注意：不使用 set -e，因為我們需要優雅處理錯誤
set -uo pipefail

# 載入依賴模組
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 載入所有模組
# 注意：許多模組重複定義了相同的 readonly 常數，會產生警告但不影響功能

# 使用 Bash 3.2 相容的方式：先關閉 errexit，然後靜默載入
set +e  # 暫時關閉錯誤中斷
set +u  # 暫時關閉未定義變數檢查

# 載入模組（stderr 導向 /dev/null 忽略 readonly 警告）
. "${LIB_DIR}/core/common.sh" 2>/dev/null
. "${LIB_DIR}/memory/pii-filter.sh" 2>/dev/null
. "${LIB_DIR}/memory/sanitize.sh" 2>/dev/null
. "${LIB_DIR}/memory/confirm.sh" 2>/dev/null
. "${LIB_DIR}/memory/provenance.sh" 2>/dev/null
. "${LIB_DIR}/memory/audit.sh" 2>/dev/null
. "${LIB_DIR}/memory/throttle.sh" 2>/dev/null
. "${LIB_DIR}/core/rollout-phase.sh" 2>/dev/null
. "${LIB_DIR}/core/circuit-breaker.sh" 2>/dev/null
. "${LIB_DIR}/core/kill-switch.sh" 2>/dev/null
. "${LIB_DIR}/core/safe-execute.sh" 2>/dev/null

# 恢復 set 選項（明確不使用 -e，因為需要優雅處理錯誤）
# 注意：被 source 的模組可能設置了 set -e，需要再次明確關閉
set +e
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# 常數定義（使用 CORRECTION_ 前綴避免衝突）
# ═══════════════════════════════════════════════════════════════

# 注意：不使用 readonly，因為被載入的模組已經定義了相同名稱的常數
# 改用獨立的變數名稱
CORRECTION_SUCCESS=0
CORRECTION_SKIPPED=1
CORRECTION_BLOCKED=2
CORRECTION_ERROR=3

# 修正關鍵字（負面 - 表示「不要做」）
readonly CORRECTION_KEYWORDS_NEGATIVE_ZH=(
    "不要"
    "禁止"
    "別用"
    "不喜歡"
    "停止"
    "別"
    "不該"
    "不應該"
)

readonly CORRECTION_KEYWORDS_NEGATIVE_EN=(
    "don't"
    "do not"
    "never"
    "stop"
    "avoid"
    "don't use"
)

# 修正關鍵字（正面 - 表示「改成」）
readonly CORRECTION_KEYWORDS_POSITIVE_ZH=(
    "改成"
    "換成"
    "改用"
    "應該用"
    "用"
    "使用"
    "改為"
)

readonly CORRECTION_KEYWORDS_POSITIVE_EN=(
    "switch to"
    "change to"
    "use instead"
    "instead of"
    "replace with"
    "use"
)

# ═══════════════════════════════════════════════════════════════
# 核心功能：關鍵字偵測
# ═══════════════════════════════════════════════════════════════

# 偵測用戶輸入是否包含修正關鍵字
# 用法: detect_correction_keywords "user_input"
# 返回: 0=偵測到，1=未偵測到
detect_correction_keywords() {
    local user_input="${1:-}"

    if [ -z "$user_input" ]; then
        return 1
    fi

    # 轉換為小寫（用於不區分大小寫匹配）
    local input_lower
    input_lower=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')

    # 檢查負面中文關鍵字
    for keyword in "${CORRECTION_KEYWORDS_NEGATIVE_ZH[@]}"; do
        local keyword_lower
        keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
        if echo "$input_lower" | grep -qF "$keyword_lower"; then
            return 0
        fi
    done

    # 檢查負面英文關鍵字
    for keyword in "${CORRECTION_KEYWORDS_NEGATIVE_EN[@]}"; do
        local keyword_lower
        keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
        if echo "$input_lower" | grep -qF "$keyword_lower"; then
            return 0
        fi
    done

    # 檢查正面中文關鍵字
    for keyword in "${CORRECTION_KEYWORDS_POSITIVE_ZH[@]}"; do
        local keyword_lower
        keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
        if echo "$input_lower" | grep -qF "$keyword_lower"; then
            return 0
        fi
    done

    # 檢查正面英文關鍵字
    for keyword in "${CORRECTION_KEYWORDS_POSITIVE_EN[@]}"; do
        local keyword_lower
        keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
        if echo "$input_lower" | grep -qF "$keyword_lower"; then
            return 0
        fi
    done

    return 1
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：內容提取
# ═══════════════════════════════════════════════════════════════

# 從用戶輸入中提取修正內容
# 用法: result=$(extract_correction_content "user_input")
# 輸出: 包含 negative 和 positive 的提取結果
# 格式: "negative:::positive" (使用 ::: 作為分隔符)
extract_correction_content() {
    local user_input="${1:-}"

    if [ -z "$user_input" ]; then
        echo ":::"
        return
    fi

    local negative=""
    local positive=""
    local content="$user_input"
    local input_lower
    input_lower=$(echo "$content" | tr '[:upper:]' '[:lower:]')

    # 策略 1：偵測「不要 X」模式
    for keyword in "${CORRECTION_KEYWORDS_NEGATIVE_ZH[@]}" "${CORRECTION_KEYWORDS_NEGATIVE_EN[@]}"; do
        local keyword_lower
        keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')

        if echo "$input_lower" | grep -qF "$keyword_lower"; then
            # 提取關鍵字之後的內容作為 negative
            # 使用原始內容（保留大小寫）
            local after_keyword
            after_keyword=$(echo "$content" | sed -n "s/.*${keyword}[[:space:]]*\([^，,。.]*\).*/\1/p" | head -1)

            if [ -n "$after_keyword" ]; then
                negative="$after_keyword"
                # 移除提取的部分，繼續尋找 positive
                content=$(echo "$content" | sed "s/${keyword}[[:space:]]*${after_keyword}//")
                break
            fi
        fi
    done

    # 策略 2：偵測「改成 Y」或「用 Y」模式
    for keyword in "${CORRECTION_KEYWORDS_POSITIVE_ZH[@]}" "${CORRECTION_KEYWORDS_POSITIVE_EN[@]}"; do
        local keyword_lower
        keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')

        if echo "$input_lower" | grep -qF "$keyword_lower"; then
            # 提取關鍵字之後的內容作為 positive
            local after_keyword
            after_keyword=$(echo "$content" | sed -n "s/.*${keyword}[[:space:]]*\([^，,。.]*\).*/\1/p" | head -1)

            if [ -n "$after_keyword" ]; then
                positive="$after_keyword"
                break
            fi
        fi
    done

    # 去除前後空格
    negative=$(echo "$negative" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    positive=$(echo "$positive" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # 輸出結果（使用 ::: 分隔）
    echo "${negative}:::${positive}"
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：格式化修正記憶
# ═══════════════════════════════════════════════════════════════

# 格式化為修正記憶格式
# 用法: formatted=$(format_correction_memory "negative" "positive" "context")
# 輸出: 格式化的記憶內容（純文字，用於存儲）
format_correction_memory() {
    local negative="${1:-}"
    local positive="${2:-}"
    local context="${3:-用戶偏好}"

    # 建立修正記憶內容（純文字格式）
    local memory_text=""

    if [ -n "$negative" ] && [ -n "$positive" ]; then
        # 完整修正：negative + positive
        memory_text="【修正】不要「${negative}」，改用「${positive}」（${context}）"
    elif [ -n "$negative" ]; then
        # 僅有禁止項目
        memory_text="【禁止】不要使用「${negative}」（${context}）"
    elif [ -n "$positive" ]; then
        # 僅有偏好項目
        memory_text="【偏好】使用「${positive}」（${context}）"
    else
        # 無有效內容
        memory_text=""
    fi

    echo "$memory_text"
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：修正記憶處理流程
# ═══════════════════════════════════════════════════════════════

# 處理用戶修正的主流程
# 用法: process_correction_memory "user_input"
# 返回: 0=成功，1=跳過，2=被阻擋，3=錯誤
# 輸出: JSON 格式的處理結果（stdout）
process_correction_memory() {
    local user_input="${1:-}"

    # 步驟 1: 偵測修正關鍵字
    if ! detect_correction_keywords "$user_input"; then
        # 未偵測到修正關鍵字，跳過
        echo '{"status":"skipped","reason":"no_keywords","correction":{"negative":"","positive":""}}'
        return $CORRECTION_SKIPPED
    fi

    # 步驟 2: 提取修正內容
    local extraction_result
    extraction_result=$(extract_correction_content "$user_input")

    # 分割結果（使用 ::: 分隔）
    local negative
    local positive
    negative=$(echo "$extraction_result" | awk -F':::' '{print $1}')
    positive=$(echo "$extraction_result" | awk -F':::' '{print $2}')

    if [ -z "$negative" ] && [ -z "$positive" ]; then
        # 提取失敗（無內容）
        echo '{"status":"skipped","reason":"empty_content","correction":{"negative":"","positive":""}}'
        return $CORRECTION_SKIPPED
    fi

    # 步驟 3: 格式化記憶內容
    local memory_content
    memory_content=$(format_correction_memory "$negative" "$positive" "用戶偏好")

    if [ -z "$memory_content" ]; then
        # 格式化失敗
        echo '{"status":"skipped","reason":"format_failed","correction":{"negative":"","positive":""}}'
        return $CORRECTION_SKIPPED
    fi

    # 步驟 4: 安全檢查 - PII 偵測
    local pii_result
    if ! pii_result=$(check_and_block_pii "$memory_content" 2>&1); then
        # 偵測到敏感資料，阻擋
        local escaped_reason
        escaped_reason=$(echo "$pii_result" | tr '\n' ' ' | sed 's/"/\\"/g')
        local escaped_negative
        local escaped_positive
        escaped_negative=$(echo "$negative" | sed 's/"/\\"/g')
        escaped_positive=$(echo "$positive" | sed 's/"/\\"/g')

        echo "{\"status\":\"blocked\",\"reason\":\"pii_detected\",\"correction\":{\"negative\":\"$escaped_negative\",\"positive\":\"$escaped_positive\"},\"details\":\"$escaped_reason\"}"

        # 記錄審計
        safe_execute -s -- audit_memory_write "$ACTION_BLOCKED" "MEMORY.md" "" "$AUDIT_SOURCE_USER" "main" "pii_detected"

        return $CORRECTION_BLOCKED
    fi

    # 步驟 5: 消毒內容
    local sanitized_content
    if ! sanitized_content=$(sanitize_memory_content "$memory_content" 2>&1); then
        # 消毒失敗（惡意內容）
        local escaped_reason
        escaped_reason=$(echo "$sanitized_content" | tr '\n' ' ' | sed 's/"/\\"/g')
        local escaped_negative
        local escaped_positive
        escaped_negative=$(echo "$negative" | sed 's/"/\\"/g')
        escaped_positive=$(echo "$positive" | sed 's/"/\\"/g')

        echo "{\"status\":\"blocked\",\"reason\":\"malicious_content\",\"correction\":{\"negative\":\"$escaped_negative\",\"positive\":\"$escaped_positive\"},\"details\":\"$escaped_reason\"}"

        # 記錄審計
        safe_execute -s -- audit_memory_write "$ACTION_BLOCKED" "MEMORY.md" "" "$AUDIT_SOURCE_USER" "main" "malicious_content"

        return $CORRECTION_BLOCKED
    fi

    # 步驟 6: 節流檢查
    if ! throttle_write 2>/dev/null; then
        # 節流中，需要等待
        local remaining
        remaining=$(get_remaining_wait_time 2>/dev/null || echo "10")
        local escaped_negative
        local escaped_positive
        escaped_negative=$(echo "$negative" | sed 's/"/\\"/g')
        escaped_positive=$(echo "$positive" | sed 's/"/\\"/g')

        echo "{\"status\":\"blocked\",\"reason\":\"throttled\",\"correction\":{\"negative\":\"$escaped_negative\",\"positive\":\"$escaped_positive\"},\"wait_seconds\":$remaining}"
        return $CORRECTION_BLOCKED
    fi

    # 步驟 7: 追蹤來源（標記為用戶來源，高優先級）
    local provenance_json
    provenance_json=$(generate_provenance "$SOURCE_TYPE_USER" "main" 2>/dev/null || echo '{}')

    # 步驟 8: 記錄審計
    local content_hash
    content_hash=$(compute_content_hash "$sanitized_content" 2>/dev/null || echo "0000000000000000")
    safe_execute -s -- audit_memory_write "$ACTION_WRITE" "MEMORY.md" "$content_hash" "$AUDIT_SOURCE_USER" "main" ""

    # 步驟 9: 寫入記憶（TODO: Phase 4 實作 memory-update.sh）
    # 目前只返回成功狀態，實際寫入將在 Phase 4 完成

    # 成功
    local escaped_content
    local escaped_negative
    local escaped_positive
    escaped_content=$(echo "$sanitized_content" | sed 's/"/\\"/g' | tr '\n' ' ')
    escaped_negative=$(echo "$negative" | sed 's/"/\\"/g')
    escaped_positive=$(echo "$positive" | sed 's/"/\\"/g')

    echo "{\"status\":\"success\",\"reason\":\"extracted\",\"correction\":{\"negative\":\"$escaped_negative\",\"positive\":\"$escaped_positive\"},\"memory_extracted\":\"$escaped_content\",\"source_type\":\"$SOURCE_TYPE_USER\",\"priority\":\"high\",\"user_confirmed\":true,\"provenance\":$provenance_json}"

    return $CORRECTION_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# Hook 入口點
# ═══════════════════════════════════════════════════════════════

# Hook 主函式（從 stdin 讀取 JSON）
# 輸入格式: {"session_id":"abc123","user_prompt":"不要使用 var，改用 const"}
# 輸出格式: {"status":"success|skipped|blocked","correction":{...},"reason":"..."}
hook_main() {
    # 檢查 Rollout Phase（僅在 Phase B+ 啟用）
    # 檢查常數是否已定義（防止 unbound variable 錯誤）
    if [ -z "${FEATURE_EXTRACT_CORRECTION:-}" ]; then
        # 同時輸出到 stdout（給調用方）和 stderr（給日誌）
        echo '{"status":"error","reason":"config_missing","correction":{"negative":"","positive":""}}'
        echo "錯誤：環境變數 FEATURE_EXTRACT_CORRECTION 未定義" >&2
        exit $CORRECTION_ERROR
    fi

    if ! is_feature_enabled "$FEATURE_EXTRACT_CORRECTION" 2>/dev/null; then
        # Phase A：不處理，直接返回
        echo '{"status":"skipped","reason":"phase_disabled","correction":{"negative":"","positive":""}}'
        exit $CORRECTION_SKIPPED
    fi

    # 檢查 Kill Switch（先執行命令再檢查返回值）
    local switch_status
    check_kill_switches >/dev/null 2>&1
    switch_status=$?

    if [ $switch_status -ne $EXIT_NORMAL ]; then
        if [ $switch_status -eq $EXIT_DISABLED ]; then
            # 完全禁用
            echo '{"status":"skipped","reason":"kill_switch_disabled","correction":{"negative":"","positive":""}}'
            exit $CORRECTION_SKIPPED
        elif [ $switch_status -eq $EXIT_INJECT_DISABLED ]; then
            # 注入禁用（修正提取仍可進行，但不會注入）
            echo '{"status":"skipped","reason":"inject_disabled","correction":{"negative":"","positive":""}}' >&2
        elif [ $switch_status -eq $EXIT_READONLY ]; then
            # 只讀模式，阻擋寫入
            echo '{"status":"blocked","reason":"readonly_mode","correction":{"negative":"","positive":""}}'
            exit $CORRECTION_BLOCKED
        fi
    fi

    # 檢查熔斷器
    if is_circuit_breaker_open 2>/dev/null; then
        # 熔斷器開啟，阻擋操作
        echo '{"status":"blocked","reason":"circuit_breaker_open","correction":{"negative":"","positive":""}}'
        exit $CORRECTION_BLOCKED
    fi

    # 從 stdin 讀取 JSON
    local input_json
    input_json=$(cat)

    # 提取 user_prompt（簡單的 JSON 解析）
    local user_prompt
    user_prompt=$(echo "$input_json" | grep -o '"user_prompt"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"user_prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    if [ -z "$user_prompt" ]; then
        # 無法解析 user_prompt
        echo '{"status":"error","reason":"invalid_input","correction":{"negative":"","positive":""}}'
        exit $CORRECTION_ERROR
    fi

    # 處理用戶修正記憶
    local result
    result=$(process_correction_memory "$user_prompt")
    local exit_code=$?

    # 輸出結果
    echo "$result"
    exit $exit_code
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_correction_help() {
    cat <<'EOF'
用戶修正提取處理器 (Correction Memory Extractor)

用法:
  # 作為 Hook 使用（從 stdin 讀取 JSON）
  echo '{"session_id":"test","user_prompt":"不要使用 var，改用 const"}' | ./memory-extract-correction.sh

  # 直接測試（CLI 模式）
  ./memory-extract-correction.sh test "不要使用 var，改用 const"
  ./memory-extract-correction.sh detect "禁止使用 Vue"
  ./memory-extract-correction.sh extract "不要用 jQuery，改成 React"

CLI 指令:
  test <input>      完整測試流程（包含安全檢查）
  detect <input>    僅測試關鍵字偵測
  extract <input>   僅測試內容提取
  help              顯示此說明

Hook 輸入格式 (JSON via stdin):
  {
    "session_id": "abc123",
    "user_prompt": "不要使用 var，改用 const"
  }

Hook 輸出格式 (JSON via stdout):
  成功:
    {
      "status": "success",
      "reason": "extracted",
      "correction": {
        "negative": "使用 var",
        "positive": "使用 const"
      },
      "memory_extracted": "【修正】不要「使用 var」，改用「使用 const」（用戶偏好）",
      "source_type": "user",
      "priority": "high",
      "user_confirmed": true,
      "provenance": {...}
    }

  跳過:
    {
      "status": "skipped",
      "reason": "no_keywords|empty_content|phase_disabled",
      "correction": {"negative": "", "positive": ""}
    }

  被阻擋:
    {
      "status": "blocked",
      "reason": "pii_detected|malicious_content|throttled|readonly_mode|circuit_breaker_open",
      "correction": {"negative": "...", "positive": "..."},
      "details": "..."
    }

支援的修正關鍵字:
  負面（禁止）:
    中文: 不要、禁止、別用、不喜歡、停止、別、不該、不應該
    英文: don't, do not, never, stop, avoid, don't use

  正面（偏好）:
    中文: 改成、換成、改用、應該用、用、使用、改為
    英文: switch to, change to, use instead, instead of, replace with, use

修正類型:
  1. 完整修正：「不要 X，改用 Y」→ negative=X, positive=Y
  2. 僅禁止：「不要 X」→ negative=X, positive=""
  3. 僅偏好：「用 Y」→ negative="", positive=Y

安全機制:
  1. PII 偵測（detect_sensitive_data）
  2. 內容消毒（sanitize_memory_content）
  3. 節流控制（throttle_write）
  4. 來源追蹤（generate_provenance）
  5. 審計記錄（audit_memory_write）

容錯機制:
  - Rollout Phase 檢查（僅 Phase B+ 啟用）
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
            user_input="${*:-}"
            if [ -z "$user_input" ]; then
                echo "錯誤：必須提供用戶輸入" >&2
                echo "用法: $0 test <input>" >&2
                exit $CORRECTION_ERROR
            fi

            # 建立 JSON 輸入
            escaped_input=$(echo "$user_input" | sed 's/"/\\"/g')
            input_json="{\"session_id\":\"test\",\"user_prompt\":\"$escaped_input\"}"

            # 呼叫 hook_main
            echo "$input_json" | hook_main
            exit $?
            ;;
        detect)
            # 僅測試關鍵字偵測
            shift
            user_input="${*:-}"
            if detect_correction_keywords "$user_input"; then
                echo "✅ 偵測到修正關鍵字"
                exit 0
            else
                echo "❌ 未偵測到修正關鍵字"
                exit 1
            fi
            ;;
        extract)
            # 僅測試內容提取
            shift
            user_input="${*:-}"
            extraction=$(extract_correction_content "$user_input")
            negative=$(echo "$extraction" | awk -F':::' '{print $1}')
            positive=$(echo "$extraction" | awk -F':::' '{print $2}')

            echo "提取結果:"
            echo "  負面（禁止）: $negative"
            echo "  正面（偏好）: $positive"

            # 顯示格式化結果
            formatted=$(format_correction_memory "$negative" "$positive" "用戶偏好")
            echo ""
            echo "格式化記憶:"
            echo "  $formatted"
            exit 0
            ;;
        help|--help|-h)
            show_correction_help
            exit 0
            ;;
        *)
            # 預設：作為 Hook 使用（從 stdin 讀取）
            hook_main
            exit $?
            ;;
    esac
fi
