#!/usr/bin/env bash
# memory-provenance.sh - 記憶來源追蹤工具
# 功能：追蹤記憶的來源（用戶明確、Agent 推論、系統生成）
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/provenance.sh"

set -euo pipefail

# 載入依賴
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/../core/common.sh"

# 載入 yaml-parser（一次性載入，避免重複 source）
if [ -z "${YAML_PARSER_LOADED:-}" ]; then
    source "${SCRIPT_DIR}/../core/yaml-parser.sh"
    readonly YAML_PARSER_LOADED=1
fi

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 返回碼（使用獨立的常數名稱避免衝突）
readonly PROVENANCE_SUCCESS=0
readonly PROVENANCE_ERROR=1
readonly PROVENANCE_INVALID_INPUT=2

# 來源類型
readonly SOURCE_TYPE_USER="user"
readonly SOURCE_TYPE_AGENT_IMPLICIT="agent_implicit"
readonly SOURCE_TYPE_SYSTEM="system"

# 確認狀態
readonly USER_CONFIRMED="confirmed"
readonly USER_PENDING="pending"

# Agent 名稱
readonly AGENT_MAIN="main"
readonly AGENT_DEVELOPER="developer"
readonly AGENT_REVIEWER="reviewer"
readonly AGENT_TESTER="tester"
readonly AGENT_DEBUGGER="debugger"
readonly AGENT_ARCHITECT="architect"
readonly AGENT_DESIGNER="designer"

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 取得當前 Session ID
# 用法: session_id=$(get_current_session_id)
# 輸出: Session ID 字串（優先順序：CLAUDE_SESSION_ID > E2E_SESSION_ID > default）
get_current_session_id() {
    local session_id="${CLAUDE_SESSION_ID:-}"

    # Fallback 到 E2E_SESSION_ID（測試環境）
    if [ -z "$session_id" ] || [ "$session_id" = "null" ]; then
        session_id="${E2E_SESSION_ID:-}"
    fi

    # Fallback 到 default
    if [ -z "$session_id" ] || [ "$session_id" = "null" ]; then
        session_id="default"
    fi

    printf '%s\n' "$session_id"
}

# 生成來源元資料
# 用法: generate_provenance source_type agent [session_id]
# 參數:
#   source_type - 來源類型 (user|agent_implicit|system)
#   agent       - Agent 名稱 (main|developer|reviewer|tester|debugger|architect|designer)
#   session_id  - 可選，Session ID（預設自動偵測）
# 輸出: JSON 格式的來源元資料
generate_provenance() {
    local source_type="${1:-}"
    local agent="${2:-$AGENT_MAIN}"
    local session_id="${3:-}"

    if [ -z "$source_type" ]; then
        echo "錯誤：generate_provenance 需要提供 source_type" >&2
        return $PROVENANCE_ERROR
    fi

    # 驗證 source_type
    case "$source_type" in
        "$SOURCE_TYPE_USER"|"$SOURCE_TYPE_AGENT_IMPLICIT"|"$SOURCE_TYPE_SYSTEM")
            # 合法
            ;;
        *)
            echo "錯誤：不合法的 source_type: $source_type" >&2
            echo "  合法值: $SOURCE_TYPE_USER, $SOURCE_TYPE_AGENT_IMPLICIT, $SOURCE_TYPE_SYSTEM" >&2
            return $PROVENANCE_ERROR
            ;;
    esac

    # 自動偵測 session_id
    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id)
    fi

    # 決定 user_confirmed 狀態
    local user_confirmed="$USER_PENDING"
    if [ "$source_type" = "$SOURCE_TYPE_USER" ]; then
        user_confirmed="$USER_CONFIRMED"
    fi

    # 取得時間戳
    local timestamp
    timestamp=$(get_timestamp)

    # 組裝 JSON（手動拼接，避免依賴 jq）
    cat <<EOF
{
  "source_type": "$source_type",
  "source_agent": "$agent",
  "session_id": "$session_id",
  "user_confirmed": "$user_confirmed",
  "created_at": "$timestamp"
}
EOF
}

# 追蹤記憶來源
# 用法: track_memory_source content source_type [agent] [session_id]
# 參數:
#   content     - 記憶內容
#   source_type - 來源類型 (user|agent_implicit|system)
#   agent       - 可選，Agent 名稱（預設 main）
#   session_id  - 可選，Session ID（預設自動偵測）
# 輸出: 帶有來源資訊的 JSON
track_memory_source() {
    local content="${1:-}"
    local source_type="${2:-}"
    local agent="${3:-$AGENT_MAIN}"
    local session_id="${4:-}"

    if [ -z "$content" ]; then
        echo "錯誤：track_memory_source 需要提供 content" >&2
        return $PROVENANCE_ERROR
    fi

    if [ -z "$source_type" ]; then
        echo "錯誤：track_memory_source 需要提供 source_type" >&2
        return $PROVENANCE_ERROR
    fi

    # 生成 provenance
    local provenance
    provenance=$(generate_provenance "$source_type" "$agent" "$session_id")

    # 轉義 content 中的特殊字元（完整版：反斜線、雙引號、Tab、換行、回車）
    local escaped_content
    # 順序重要：反斜線必須最先處理
    escaped_content=$(printf '%s' "$content" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | tr '\n' ' ' | tr '\r' ' ')

    # 組裝最終 JSON
    cat <<EOF
{
  "content": "$escaped_content",
  "provenance": $provenance
}
EOF
}

# 標記用戶已確認
# 用法: mark_user_confirmed memory_file
# 參數: memory_file - MEMORY.md 檔案路徑
# 返回: 0=成功，1=失敗
mark_user_confirmed() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ]; then
        echo "錯誤：mark_user_confirmed 需要提供 memory_file" >&2
        return $PROVENANCE_ERROR
    fi

    if [ ! -f "$memory_file" ]; then
        echo "錯誤：檔案不存在: $memory_file" >&2
        return $PROVENANCE_ERROR
    fi

    # 檢查是否有 frontmatter（yaml-parser.sh 已在頂部載入）
    if ! has_frontmatter "$memory_file"; then
        echo "錯誤：記憶檔案無 frontmatter: $memory_file" >&2
        return $PROVENANCE_ERROR
    fi

    # 更新 user_confirmed 欄位
    if ! update_frontmatter "$memory_file" "user_confirmed" "$USER_CONFIRMED"; then
        echo "錯誤：無法更新 user_confirmed 欄位" >&2
        return $PROVENANCE_ERROR
    fi

    return $PROVENANCE_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 驗證 Agent 名稱
# 用法: validate_agent_name agent_name
# 返回: 0=合法，1=不合法
validate_agent_name() {
    local agent_name="${1:-}"

    case "$agent_name" in
        "$AGENT_MAIN"|"$AGENT_DEVELOPER"|"$AGENT_REVIEWER"|"$AGENT_TESTER"|"$AGENT_DEBUGGER"|"$AGENT_ARCHITECT"|"$AGENT_DESIGNER")
            return $PROVENANCE_SUCCESS
            ;;
        *)
            return $PROVENANCE_ERROR
            ;;
    esac
}

# 顯示支援的 Agent 列表
# 用法: show_supported_agents
show_supported_agents() {
    cat <<EOF
支援的 Agent 名稱：
  - $AGENT_MAIN
  - $AGENT_DEVELOPER
  - $AGENT_REVIEWER
  - $AGENT_TESTER
  - $AGENT_DEBUGGER
  - $AGENT_ARCHITECT
  - $AGENT_DESIGNER
EOF
}

# 顯示使用說明
show_provenance_help() {
    cat <<'EOF'
記憶來源追蹤工具 (Memory Provenance Tracker)

用法:
  source hooks/scripts/lib/memory/provenance.sh

函式:
  get_current_session_id
    取得當前 Session ID
    返回: Session ID 字串

  generate_provenance <source_type> <agent> [session_id]
    生成來源元資料
    參數:
      source_type - 來源類型 (user|agent_implicit|system)
      agent       - Agent 名稱 (main|developer|reviewer|...)
      session_id  - 可選，Session ID（預設自動偵測）
    輸出: JSON 格式的來源元資料

  track_memory_source <content> <source_type> [agent] [session_id]
    追蹤記憶來源
    參數:
      content     - 記憶內容
      source_type - 來源類型
      agent       - 可選，Agent 名稱（預設 main）
      session_id  - 可選，Session ID
    輸出: 帶有來源資訊的 JSON

  mark_user_confirmed <memory_file>
    標記記憶為用戶已確認
    參數: memory_file - MEMORY.md 檔案路徑
    返回: 0=成功，1=失敗

  validate_agent_name <agent_name>
    驗證 Agent 名稱是否合法
    返回: 0=合法，1=不合法

  show_supported_agents
    顯示支援的 Agent 列表

範例:
  # 取得當前 Session ID
  session_id=$(get_current_session_id)
  echo "當前 Session: $session_id"

  # 生成用戶來源的元資料
  provenance=$(generate_provenance "user" "main")
  echo "$provenance"

  # 追蹤記憶來源
  memory_json=$(track_memory_source "用戶偏好使用 TypeScript" "user" "main")
  echo "$memory_json"

  # 追蹤 Agent 推論的記憶
  memory_json=$(track_memory_source "專案使用 Prisma ORM" "agent_implicit" "developer")
  echo "$memory_json"

  # 標記用戶已確認
  mark_user_confirmed ".claude/memory/sessions/session-123.md"

來源類型:
  - user           : 用戶明確提供的記憶
  - agent_implicit : Agent 推論得出的記憶
  - system         : 系統自動生成的記憶

確認狀態:
  - confirmed : 用戶已確認（來源為 user 時自動設定）
  - pending   : 待確認（來源為 agent_implicit 或 system 時）

支援的 Agent:
  - main       : Main Agent
  - developer  : Developer Agent
  - reviewer   : Reviewer Agent
  - tester     : Tester Agent
  - debugger   : Debugger Agent
  - architect  : Architect Agent
  - designer   : Designer Agent
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        session-id)
            get_current_session_id
            exit $?
            ;;
        generate)
            shift
            generate_provenance "$@"
            exit $?
            ;;
        track)
            shift
            track_memory_source "$@"
            exit $?
            ;;
        mark-confirmed)
            shift
            mark_user_confirmed "$@"
            exit $?
            ;;
        validate)
            shift
            validate_agent_name "$@"
            exit $?
            ;;
        agents)
            show_supported_agents
            exit 0
            ;;
        help|--help|-h|*)
            show_provenance_help
            exit 0
            ;;
    esac
fi
