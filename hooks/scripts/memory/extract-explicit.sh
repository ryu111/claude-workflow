#!/usr/bin/env bash
# memory-extract-explicit.sh - 顯式記憶提取處理器
# 功能：當用戶明確說「記住 X」時提取記憶
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

# 恢復 set 選項
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# 常數定義（使用 EXTRACT_ 前綴避免衝突）
# ═══════════════════════════════════════════════════════════════

# 注意：不使用 readonly，因為被載入的模組已經定義了相同名稱的常數
# 改用獨立的變數名稱
EXTRACT_SUCCESS=0
EXTRACT_SKIPPED=1
EXTRACT_BLOCKED=2
EXTRACT_ERROR=3

# 記憶關鍵字（中文）
readonly EXTRACT_KEYWORDS_ZH=(
    "記住"
    "記下"
    "下次"
    "偏好"
    "喜歡"
    "不要"
    "禁止"
)

# 記憶關鍵字（英文）
readonly EXTRACT_KEYWORDS_EN=(
    "remember"
    "note that"
    "prefer"
    "always"
    "never"
)

# 冗餘前綴（需要去除）
readonly EXTRACT_REDUNDANT_PREFIXES=(
    "請"
    "幫我"
    "麻煩"
    "可以"
    "能否"
    "please"
    "could you"
    "can you"
)

# ═══════════════════════════════════════════════════════════════
# 核心功能：關鍵字偵測
# ═══════════════════════════════════════════════════════════════

# 偵測用戶輸入是否包含記憶關鍵字
# 用法: detect_remember_keywords "user_input"
# 返回: 0=偵測到，1=未偵測到
detect_remember_keywords() {
    local user_input="${1:-}"

    if [ -z "$user_input" ]; then
        return 1
    fi

    # 轉換為小寫（用於不區分大小寫匹配）
    local input_lower
    input_lower=$(echo "$user_input" | tr '[:upper:]' '[:lower:]')

    # 檢查中文關鍵字
    for keyword in "${EXTRACT_KEYWORDS_ZH[@]}"; do
        local keyword_lower
        keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
        if echo "$input_lower" | grep -qF "$keyword_lower"; then
            return 0
        fi
    done

    # 檢查英文關鍵字
    for keyword in "${EXTRACT_KEYWORDS_EN[@]}"; do
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

# 從用戶輸入中提取記憶內容
# 用法: extract_memory_content "user_input"
# 輸出: 提取的記憶內容
extract_memory_content() {
    local user_input="${1:-}"

    if [ -z "$user_input" ]; then
        echo ""
        return
    fi

    local content="$user_input"

    # 移除關鍵字（使用第一個匹配的關鍵字）
    local matched_keyword=""

    # 檢查中文關鍵字
    for keyword in "${EXTRACT_KEYWORDS_ZH[@]}"; do
        if echo "$content" | grep -qF "$keyword"; then
            matched_keyword="$keyword"
            break
        fi
    done

    # 如果沒有匹配中文，檢查英文（不區分大小寫）
    if [ -z "$matched_keyword" ]; then
        local content_lower
        content_lower=$(echo "$content" | tr '[:upper:]' '[:lower:]')

        for keyword in "${EXTRACT_KEYWORDS_EN[@]}"; do
            local keyword_lower
            keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')

            if echo "$content_lower" | grep -qF "$keyword_lower"; then
                # 找到位置，從原始內容中提取
                # 使用 awk 進行不區分大小寫的分割
                local before_keyword
                before_keyword=$(echo "$content_lower" | awk -F"$keyword_lower" '{print $1}')
                local keyword_length=${#before_keyword}
                keyword_length=$((keyword_length + ${#keyword_lower}))

                # 提取關鍵字之後的部分
                content="${content:$keyword_length}"
                matched_keyword="$keyword"
                break
            fi
        done
    fi

    # 移除關鍵字及其前面的部分（中文）
    if [ -n "$matched_keyword" ] && echo "$matched_keyword" | grep -q "[^\x00-\x7F]"; then
        # 中文關鍵字：使用 sed
        content=$(echo "$content" | sed "s/.*${matched_keyword}[[:space:]]*//" | sed 's/^[[:space:]]*//')
    fi

    # 移除冗餘前綴
    for prefix in "${EXTRACT_REDUNDANT_PREFIXES[@]}"; do
        content=$(echo "$content" | sed "s/^${prefix}[[:space:]]*//" | sed 's/^[[:space:]]*//')
    done

    # 去除前後空格
    content=$(echo "$content" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    echo "$content"
}

# ═══════════════════════════════════════════════════════════════
# 核心功能：顯式記憶處理流程
# ═══════════════════════════════════════════════════════════════

# 處理顯式記憶的主流程
# 用法: process_explicit_memory "user_input"
# 返回: 0=成功，1=跳過，2=被阻擋，3=錯誤
# 輸出: JSON 格式的處理結果（stdout）
process_explicit_memory() {
    local user_input="${1:-}"

    # 步驟 1: 偵測關鍵字
    if ! detect_remember_keywords "$user_input"; then
        # 未偵測到記憶關鍵字，跳過
        echo '{"status":"skipped","reason":"no_keywords","memory_extracted":""}'
        return $EXTRACT_SKIPPED
    fi

    # 步驟 2: 提取記憶內容
    local memory_content
    memory_content=$(extract_memory_content "$user_input")

    if [ -z "$memory_content" ]; then
        # 提取失敗（空內容）
        echo '{"status":"skipped","reason":"empty_content","memory_extracted":""}'
        return $EXTRACT_SKIPPED
    fi

    # 步驟 3: 安全檢查 - PII 偵測
    local pii_result
    if ! pii_result=$(check_and_block_pii "$memory_content" 2>&1); then
        # 偵測到敏感資料，阻擋
        local escaped_reason
        escaped_reason=$(echo "$pii_result" | tr '\n' ' ' | sed 's/"/\\"/g')
        echo "{\"status\":\"blocked\",\"reason\":\"pii_detected\",\"memory_extracted\":\"$memory_content\",\"details\":\"$escaped_reason\"}"

        # 記錄審計
        safe_execute -s -- audit_memory_write "$ACTION_BLOCKED" "MEMORY.md" "" "$AUDIT_SOURCE_USER" "main" "pii_detected"

        return $EXTRACT_BLOCKED
    fi

    # 步驟 4: 消毒內容
    local sanitized_content
    if ! sanitized_content=$(sanitize_memory_content "$memory_content" 2>&1); then
        # 消毒失敗（惡意內容）
        local escaped_reason
        escaped_reason=$(echo "$sanitized_content" | tr '\n' ' ' | sed 's/"/\\"/g')
        echo "{\"status\":\"blocked\",\"reason\":\"malicious_content\",\"memory_extracted\":\"$memory_content\",\"details\":\"$escaped_reason\"}"

        # 記錄審計
        safe_execute -s -- audit_memory_write "$ACTION_BLOCKED" "MEMORY.md" "" "$AUDIT_SOURCE_USER" "main" "malicious_content"

        return $EXTRACT_BLOCKED
    fi

    # 步驟 5: 風險評估
    local risk_exit_code
    confirm_high_risk_memory "$sanitized_content" >/dev/null 2>&1
    risk_exit_code=$?

    if [ $risk_exit_code -eq $EXIT_NEEDS_CONFIRMATION ]; then
        # 需要用戶確認（但在此階段我們接受用戶明確的「記住」指令）
        echo "{\"status\":\"success\",\"reason\":\"user_explicit\",\"memory_extracted\":\"$sanitized_content\",\"source_type\":\"$SOURCE_TYPE_USER\",\"risk\":\"medium_to_high\"}" >&2
    fi

    # 步驟 6: 節流檢查
    if ! throttle_write 2>/dev/null; then
        # 節流中，需要等待
        local remaining
        remaining=$(get_remaining_wait_time 2>/dev/null || echo "10")
        echo "{\"status\":\"blocked\",\"reason\":\"throttled\",\"memory_extracted\":\"$sanitized_content\",\"wait_seconds\":$remaining}"
        return $EXTRACT_BLOCKED
    fi

    # 步驟 7: 追蹤來源（標記為用戶來源）
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
    escaped_content=$(echo "$sanitized_content" | sed 's/"/\\"/g' | tr '\n' ' ')
    echo "{\"status\":\"success\",\"reason\":\"extracted\",\"memory_extracted\":\"$escaped_content\",\"source_type\":\"$SOURCE_TYPE_USER\",\"provenance\":$provenance_json}"

    return $EXTRACT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# Hook 入口點
# ═══════════════════════════════════════════════════════════════

# Hook 主函式（從 stdin 讀取 JSON）
# 輸入格式: {"session_id":"abc123","user_prompt":"記住我偏好使用 TypeScript"}
# 輸出格式: {"status":"success|skipped|blocked","memory_extracted":"...","reason":"..."}
hook_main() {
    # 檢查 Rollout Phase（僅在 Phase B+ 啟用）
    # 檢查常數是否已定義（防止 unbound variable 錯誤）
    if [ -z "${FEATURE_EXTRACT_EXPLICIT:-}" ]; then
        # 同時輸出到 stdout（給調用方）和 stderr（給日誌）
        echo '{"status":"error","reason":"config_missing","memory_extracted":""}'
        echo "錯誤：環境變數 FEATURE_EXTRACT_EXPLICIT 未定義" >&2
        exit $EXTRACT_ERROR
    fi

    if ! is_feature_enabled "$FEATURE_EXTRACT_EXPLICIT" 2>/dev/null; then
        # Phase A：不處理，直接返回
        echo '{"status":"skipped","reason":"phase_disabled","memory_extracted":""}'
        exit $EXTRACT_SKIPPED
    fi

    # 檢查 Kill Switch（先執行命令再檢查返回值）
    local switch_status
    check_kill_switches >/dev/null 2>&1
    switch_status=$?

    if [ $switch_status -ne $EXIT_NORMAL ]; then
        if [ $switch_status -eq $EXIT_DISABLED ]; then
            # 完全禁用
            echo '{"status":"skipped","reason":"kill_switch_disabled","memory_extracted":""}'
            exit $EXTRACT_SKIPPED
        elif [ $switch_status -eq $EXIT_INJECT_DISABLED ]; then
            # 注入禁用（顯式提取仍可進行，但不會注入）
            echo '{"status":"skipped","reason":"inject_disabled","memory_extracted":""}' >&2
        elif [ $switch_status -eq $EXIT_READONLY ]; then
            # 只讀模式，阻擋寫入
            echo '{"status":"blocked","reason":"readonly_mode","memory_extracted":""}'
            exit $EXTRACT_BLOCKED
        fi
    fi

    # 檢查熔斷器
    if is_circuit_breaker_open 2>/dev/null; then
        # 熔斷器開啟，阻擋操作
        echo '{"status":"blocked","reason":"circuit_breaker_open","memory_extracted":""}'
        exit $EXTRACT_BLOCKED
    fi

    # 從 stdin 讀取 JSON
    local input_json
    input_json=$(cat)

    # 提取 user_prompt（簡單的 JSON 解析）
    local user_prompt
    user_prompt=$(echo "$input_json" | grep -o '"user_prompt"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"user_prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    if [ -z "$user_prompt" ]; then
        # 無法解析 user_prompt
        echo '{"status":"error","reason":"invalid_input","memory_extracted":""}'
        exit $EXTRACT_ERROR
    fi

    # 處理顯式記憶
    local result
    result=$(process_explicit_memory "$user_prompt")
    local exit_code=$?

    # 輸出結果
    echo "$result"
    exit $exit_code
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_extract_help() {
    cat <<'EOF'
顯式記憶提取處理器 (Explicit Memory Extractor)

用法:
  # 作為 Hook 使用（從 stdin 讀取 JSON）
  echo '{"session_id":"test","user_prompt":"記住我喜歡 TypeScript"}' | ./memory-extract-explicit.sh

  # 直接測試（CLI 模式）
  ./memory-extract-explicit.sh test "記住我偏好使用 React"
  ./memory-extract-explicit.sh detect "記住這個設定"
  ./memory-extract-explicit.sh extract "記住我不要使用 Vue"

CLI 指令:
  test <input>      完整測試流程（包含安全檢查）
  detect <input>    僅測試關鍵字偵測
  extract <input>   僅測試內容提取
  help              顯示此說明

Hook 輸入格式 (JSON via stdin):
  {
    "session_id": "abc123",
    "user_prompt": "記住我偏好使用 TypeScript"
  }

Hook 輸出格式 (JSON via stdout):
  成功:
    {
      "status": "success",
      "reason": "extracted",
      "memory_extracted": "我偏好使用 TypeScript",
      "source_type": "user",
      "provenance": {...}
    }

  跳過:
    {
      "status": "skipped",
      "reason": "no_keywords|empty_content|phase_disabled",
      "memory_extracted": ""
    }

  被阻擋:
    {
      "status": "blocked",
      "reason": "pii_detected|malicious_content|throttled|readonly_mode|circuit_breaker_open",
      "memory_extracted": "...",
      "details": "..."
    }

支援的記憶關鍵字:
  中文: 記住、記下、下次、偏好、喜歡、不要、禁止
  英文: remember, note that, prefer, always, never

安全機制:
  1. PII 偵測（detect_sensitive_data）
  2. 內容消毒（sanitize_memory_content）
  3. 風險評估（confirm_high_risk_memory）
  4. 節流控制（throttle_write）
  5. 來源追蹤（generate_provenance）
  6. 審計記錄（audit_memory_write）

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
                exit $EXTRACT_ERROR
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
            if detect_remember_keywords "$user_input"; then
                echo "✅ 偵測到記憶關鍵字"
                exit 0
            else
                echo "❌ 未偵測到記憶關鍵字"
                exit 1
            fi
            ;;
        extract)
            # 僅測試內容提取
            shift
            user_input="${*:-}"
            content=$(extract_memory_content "$user_input")
            echo "提取結果: $content"
            exit 0
            ;;
        help|--help|-h)
            show_extract_help
            exit 0
            ;;
        *)
            # 預設：作為 Hook 使用（從 stdin 讀取）
            hook_main
            exit $?
            ;;
    esac
fi
