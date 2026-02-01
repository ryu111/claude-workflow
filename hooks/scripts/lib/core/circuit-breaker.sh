#!/bin/bash
# circuit-breaker.sh - 熔斷器機制
# 功能：防止系統連續失敗時無限重試
# 邏輯：連續 5 次失敗 → 禁用 30 分鐘

set -euo pipefail

# 載入共用工具函式
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

readonly HEALTH_FILE="${PWD}/.claude/memory/.health"
readonly MAX_FAILURES=5
readonly COOLDOWN_MINUTES=30
readonly STATUS_HEALTHY="healthy"
readonly STATUS_DEGRADED="degraded"
readonly STATUS_DISABLED="disabled"

# ═══════════════════════════════════════════════════════════════
# 工具函式
# ═══════════════════════════════════════════════════════════════
# 注意：get_timestamp() 和 get_unix_timestamp() 已從 common.sh 載入

# 初始化健康狀態檔案
init_health_file() {
    if [ ! -f "$HEALTH_FILE" ]; then
        ensure_directory "$(dirname "$HEALTH_FILE")"
        local timestamp=$(get_timestamp)
        cat > "$HEALTH_FILE" <<EOF
{
  "status": "$STATUS_HEALTHY",
  "failure_count": 0,
  "last_failure": null,
  "disabled_until": null,
  "created_at": "$timestamp",
  "updated_at": "$timestamp"
}
EOF
    fi
}

# 原子性寫入 JSON 檔案
atomic_write() {
    local content="$1"
    local temp_file="${HEALTH_FILE}.tmp.$$"

    echo "$content" > "$temp_file"
    mv "$temp_file" "$HEALTH_FILE"
}

# 讀取健康狀態
get_health_status() {
    init_health_file

    if ! jq -e '.' "$HEALTH_FILE" >/dev/null 2>&1; then
        # 檔案損壞，重新初始化
        rm -f "$HEALTH_FILE"
        init_health_file
    fi

    cat "$HEALTH_FILE"
}

# 更新健康狀態
update_health_status() {
    local status="$1"
    local failure_count="$2"
    local last_failure="${3:-null}"
    local disabled_until="${4:-null}"

    local timestamp=$(get_timestamp)

    local json=$(cat <<EOF
{
  "status": "$status",
  "failure_count": $failure_count,
  "last_failure": $last_failure,
  "disabled_until": $disabled_until,
  "updated_at": "$timestamp"
}
EOF
)

    atomic_write "$json"
}

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 記錄一次失敗
# 用法: record_failure
# 返回: 0=成功記錄，1=已達到熔斷閾值
record_failure() {
    init_health_file

    local health=$(get_health_status)
    local current_count=$(echo "$health" | jq -r '.failure_count // 0')
    local new_count=$((current_count + 1))
    local timestamp=$(get_timestamp)

    if [ "$new_count" -ge "$MAX_FAILURES" ]; then
        # 達到熔斷閾值，開啟熔斷器
        open_circuit_breaker
        return 1
    else
        # 更新失敗計數
        if [ "$new_count" -ge 3 ]; then
            # 3+ 次失敗，進入 degraded 狀態
            update_health_status "$STATUS_DEGRADED" "$new_count" "\"$timestamp\"" "null"
        else
            # 1-2 次失敗，保持 healthy
            update_health_status "$STATUS_HEALTHY" "$new_count" "\"$timestamp\"" "null"
        fi
        return 0
    fi
}

# 開啟熔斷器（禁用 30 分鐘）
# 用法: open_circuit_breaker
open_circuit_breaker() {
    init_health_file

    local current_time=$(get_unix_timestamp)
    local disabled_until=$((current_time + COOLDOWN_MINUTES * 60))
    local timestamp=$(get_timestamp)
    local disabled_until_iso=$(date -u -r "$disabled_until" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$disabled_until" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)

    update_health_status "$STATUS_DISABLED" "$MAX_FAILURES" "\"$timestamp\"" "\"$disabled_until_iso\""

    echo "⚠️  熔斷器已開啟：連續 $MAX_FAILURES 次失敗，系統將禁用 $COOLDOWN_MINUTES 分鐘" >&2
    echo "   恢復時間: $disabled_until_iso" >&2
}

# 檢查熔斷器是否開啟
# 用法: is_circuit_breaker_open
# 返回: 0=開啟（阻擋），1=關閉（允許）
# 副作用: 若冷卻期已過，自動重置為 healthy
is_circuit_breaker_open() {
    init_health_file

    local health=$(get_health_status)
    local status=$(echo "$health" | jq -r '.status // "healthy"')

    # 狀態不是 disabled，熔斷器關閉
    if [ "$status" != "$STATUS_DISABLED" ]; then
        return 1
    fi

    # 檢查冷卻期是否已過
    local disabled_until=$(echo "$health" | jq -r '.disabled_until // null')
    if [ "$disabled_until" = "null" ]; then
        # 沒有設定過期時間，異常狀態，重置為 healthy
        reset_circuit_breaker
        return 1
    fi

    # 比較當前時間與過期時間
    local current_time=$(get_unix_timestamp)
    local disabled_until_unix

    # 跨平台日期解析
    if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$disabled_until" +%s >/dev/null 2>&1; then
        # macOS - 必須設定 TZ=UTC 確保正確解析 UTC 時間
        disabled_until_unix=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$disabled_until" +%s)
    else
        # Linux
        disabled_until_unix=$(date -d "$disabled_until" +%s)
    fi

    if [ "$current_time" -ge "$disabled_until_unix" ]; then
        # 冷卻期已過，自動重置
        reset_circuit_breaker
        echo "✅ 熔斷器已自動恢復（冷卻期結束）" >&2
        return 1
    fi

    # 熔斷器仍在開啟狀態
    local remaining_seconds=$((disabled_until_unix - current_time))
    local remaining_minutes=$((remaining_seconds / 60))
    echo "🚫 熔斷器已開啟：剩餘冷卻時間 $remaining_minutes 分鐘" >&2
    return 0
}

# 重置熔斷器（手動）
# 用法: reset_circuit_breaker
reset_circuit_breaker() {
    init_health_file

    update_health_status "$STATUS_HEALTHY" "0" "null" "null"
    echo "✅ 熔斷器已重置為 healthy 狀態" >&2
}

# 取得當前狀態（供外部查詢）
# 用法: get_circuit_breaker_status
# 輸出: JSON 格式的健康狀態
get_circuit_breaker_status() {
    init_health_file
    get_health_status
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（可選）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        record-failure)
            record_failure
            ;;
        open)
            open_circuit_breaker
            ;;
        is-open)
            if is_circuit_breaker_open; then
                echo "disabled"
                exit 0
            else
                echo "enabled"
                exit 1
            fi
            ;;
        reset)
            reset_circuit_breaker
            ;;
        status)
            get_circuit_breaker_status | jq '.'
            ;;
        *)
            echo "用法: $0 {record-failure|open|is-open|reset|status}" >&2
            echo "" >&2
            echo "指令:" >&2
            echo "  record-failure  記錄一次失敗" >&2
            echo "  open            強制開啟熔斷器" >&2
            echo "  is-open         檢查熔斷器狀態" >&2
            echo "  reset           重置熔斷器" >&2
            echo "  status          顯示完整狀態" >&2
            exit 1
            ;;
    esac
fi
