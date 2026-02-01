#!/bin/bash
# memory-throttle.sh - 記憶寫入節流機制
# 功能：
#   1. 限制記憶寫入頻率，防止 DoS 攻擊
#   2. 檢查距離上次寫入的時間間隔
#   3. 提供強制跳過節流的機制
#   4. 從 config.yaml 讀取節流間隔配置
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-throttle.sh"

set -euo pipefail

# 載入共用工具函式
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/../core/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 記憶目錄
readonly THROTTLE_MEMORY_DIR="${PWD}/.claude/memory"
readonly THROTTLE_CONFIG_FILE="${THROTTLE_MEMORY_DIR}/config.yaml"
readonly THROTTLE_FILE="${THROTTLE_MEMORY_DIR}/.write-throttle"

# 預設節流間隔（秒）
readonly THROTTLE_DEFAULT_INTERVAL=10

# 返回碼
readonly THROTTLE_ALLOWED=0     # 允許寫入
readonly THROTTLE_WAIT=1        # 需要等待
readonly THROTTLE_ERROR=2       # 檢查失敗

# ═══════════════════════════════════════════════════════════════
# 工具函式
# ═══════════════════════════════════════════════════════════════

# 取得節流間隔（秒）
# 用法: interval=$(get_throttle_interval)
# 輸出: 節流間隔（秒）
# 返回: 0=成功
get_throttle_interval() {
    # 如果 config.yaml 存在，嘗試讀取 memory.throttle_interval_seconds
    if [ -f "$THROTTLE_CONFIG_FILE" ]; then
        local interval
        # 使用 grep + sed 解析 YAML（避免依賴 yq）
        # 搜尋 throttle_interval_seconds: 10 這樣的行
        interval=$(grep -E '^\s*throttle_interval_seconds:\s*[0-9]+' "$THROTTLE_CONFIG_FILE" 2>/dev/null | sed -E 's/^[^:]*:[[:space:]]*([0-9]+).*/\1/' || printf "")

        # 去除可能的空格
        interval=$(printf "%s" "$interval" | tr -d ' ')

        # 驗證 interval 是否為有效數字
        if [ -n "$interval" ] && [ "$interval" -eq "$interval" ] 2>/dev/null && [ "$interval" -gt 0 ]; then
            printf "%s\n" "$interval"
            return $THROTTLE_ALLOWED
        fi
    fi

    # 使用預設值
    printf "%s\n" "$THROTTLE_DEFAULT_INTERVAL"
    return $THROTTLE_ALLOWED
}

# 取得上次寫入的時間戳（Unix timestamp）
# 用法: last_time=$(get_last_write_time)
# 輸出: Unix 時間戳（秒），如果檔案不存在返回 0
# 返回: 0=成功
get_last_write_time() {
    if [ ! -f "$THROTTLE_FILE" ]; then
        printf "0\n"
        return $THROTTLE_ALLOWED
    fi

    # 讀取時間戳（檔案內容應該是單一數字）
    local last_time
    last_time=$(cat "$THROTTLE_FILE" 2>/dev/null | tr -d ' \n\r' || printf "0")

    # 驗證是否為有效數字
    if [ -n "$last_time" ] && [ "$last_time" -eq "$last_time" ] 2>/dev/null; then
        printf "%s\n" "$last_time"
    else
        printf "0\n"
    fi

    return $THROTTLE_ALLOWED
}

# 更新寫入時間戳
# 用法: update_write_time
# 說明: 將當前時間寫入 .write-throttle 檔案
# 返回: 0=成功，2=失敗
update_write_time() {
    # 確保記憶目錄存在
    ensure_directory "$THROTTLE_MEMORY_DIR" || return $THROTTLE_ERROR

    # 取得當前時間戳
    local current_time
    current_time=$(get_unix_timestamp)

    # 寫入時間戳
    if ! printf "%s\n" "$current_time" > "$THROTTLE_FILE" 2>/dev/null; then
        printf "錯誤：無法更新寫入時間戳: %s\n" "$THROTTLE_FILE" >&2
        return $THROTTLE_ERROR
    fi

    # 設定檔案權限（防止被其他用戶修改）
    chmod 600 "$THROTTLE_FILE" 2>/dev/null || true

    return $THROTTLE_ALLOWED
}

# 取得還需要等待的時間（秒）
# 用法: remaining=$(get_remaining_wait_time)
# 輸出: 剩餘等待時間（秒），如果可以寫入則返回 0
# 返回: 0=成功
get_remaining_wait_time() {
    local last_time
    last_time=$(get_last_write_time)

    local current_time
    current_time=$(get_unix_timestamp)

    local interval
    interval=$(get_throttle_interval)

    # 計算經過的時間
    local elapsed=$((current_time - last_time))

    # 如果經過時間 >= 間隔，可以寫入
    if [ "$elapsed" -ge "$interval" ]; then
        printf "0\n"
        return $THROTTLE_ALLOWED
    fi

    # 計算剩餘等待時間
    local remaining=$((interval - elapsed))
    printf "%s\n" "$remaining"
    return $THROTTLE_ALLOWED
}

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 檢查是否允許寫入（節流機制）
# 用法: throttle_write
# 返回: 0=允許寫入（並自動更新時間戳），1=需要等待，2=檢查失敗
throttle_write() {
    local last_time
    last_time=$(get_last_write_time)

    local current_time
    current_time=$(get_unix_timestamp)

    local interval
    interval=$(get_throttle_interval)

    # 計算經過的時間
    local elapsed=$((current_time - last_time))

    # 如果經過時間 < 間隔，需要等待
    if [ "$elapsed" -lt "$interval" ]; then
        local remaining=$((interval - elapsed))
        printf "節流：距離上次寫入僅 %d 秒，需等待 %d 秒\n" "$elapsed" "$remaining" >&2
        return $THROTTLE_WAIT
    fi

    # 允許寫入，更新時間戳
    if ! update_write_time; then
        printf "錯誤：無法更新寫入時間戳\n" >&2
        return $THROTTLE_ERROR
    fi

    return $THROTTLE_ALLOWED
}

# 強制允許下一次寫入（跳過節流）
# 用法: force_allow_write
# 說明: 清除節流檔案，允許立即寫入
# 返回: 0=成功，2=失敗
force_allow_write() {
    if [ -f "$THROTTLE_FILE" ]; then
        if ! rm -f "$THROTTLE_FILE" 2>/dev/null; then
            printf "錯誤：無法刪除節流檔案: %s\n" "$THROTTLE_FILE" >&2
            return $THROTTLE_ERROR
        fi
        printf "已強制允許下次寫入（已清除節流記錄）\n" >&2
    else
        printf "節流檔案不存在，下次寫入已允許\n" >&2
    fi

    return $THROTTLE_ALLOWED
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_throttle_help() {
    cat <<'EOF'
記憶寫入節流工具 (Memory Write Throttle)

用法:
  source memory-throttle.sh

函式:
  throttle_write
    檢查是否允許寫入（節流機制）
    返回: 0=允許寫入（自動更新時間戳），1=需要等待，2=檢查失敗
    說明: 如果距離上次寫入 < 節流間隔，返回 1

  get_last_write_time
    取得上次寫入的時間戳（Unix timestamp）
    輸出: Unix 時間戳（秒），如果檔案不存在返回 0
    返回: 0=成功

  update_write_time
    更新寫入時間戳
    說明: 將當前時間寫入 .write-throttle 檔案
    返回: 0=成功，2=失敗

  get_throttle_interval
    取得節流間隔（秒）
    說明: 從 config.yaml 讀取 throttle_interval_seconds，預設 10 秒
    輸出: 節流間隔（秒）
    返回: 0=成功

  get_remaining_wait_time
    取得還需要等待的時間（秒）
    輸出: 剩餘等待時間（秒），如果可以寫入則返回 0
    返回: 0=成功

  force_allow_write
    強制允許下一次寫入（跳過節流）
    說明: 清除節流檔案，允許立即寫入
    返回: 0=成功，2=失敗

CLI 用法:
  # 檢查是否允許寫入
  ./memory-throttle.sh check

  # 強制允許下次寫入
  ./memory-throttle.sh force

  # 取得剩餘等待時間
  ./memory-throttle.sh wait-time

  # 取得節流間隔
  ./memory-throttle.sh interval

  # 重置節流（清除時間戳）
  ./memory-throttle.sh reset

範例:
  # 檢查是否允許寫入
  if throttle_write; then
      # 允許寫入（時間戳已自動更新）
      echo "寫入成功"
  else
      # 需要等待
      remaining=$(get_remaining_wait_time)
      echo "請等待 $remaining 秒後再寫入"
  fi

  # 取得節流間隔
  interval=$(get_throttle_interval)
  echo "節流間隔: $interval 秒"

  # 強制允許寫入
  force_allow_write

配置:
  節流間隔可在 config.yaml 中設定:
    memory:
      throttle_interval_seconds: 10

  預設值: 10 秒

節流檔案位置:
  .claude/memory/.write-throttle

返回碼:
  0 - 允許寫入 / 成功
  1 - 需要等待
  2 - 檢查失敗
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        check)
            # 檢查是否允許寫入（不更新時間戳）
            remaining=$(get_remaining_wait_time)
            if [ "$remaining" -eq 0 ]; then
                printf "允許寫入\n"
                exit $THROTTLE_ALLOWED
            else
                printf "需要等待 %d 秒\n" "$remaining"
                exit $THROTTLE_WAIT
            fi
            ;;
        force)
            # 強制允許下次寫入
            force_allow_write
            exit $?
            ;;
        wait-time)
            # 取得剩餘等待時間
            get_remaining_wait_time
            exit $?
            ;;
        interval)
            # 取得節流間隔
            get_throttle_interval
            exit $?
            ;;
        reset)
            # 重置節流（清除時間戳）
            force_allow_write
            exit $?
            ;;
        help|--help|-h|*)
            show_throttle_help
            exit 0
            ;;
    esac
fi
