#!/bin/bash
# safe-execute.sh - 容錯執行包裝函式
# 功能：提供命令執行的容錯包裝，支援超時控制和失敗處理
# 用法：source 此檔案後呼叫 safe_execute()

set -euo pipefail

# 載入共用工具函式
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/circuit-breaker.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

readonly DEFAULT_TIMEOUT=5
readonly EXIT_SUCCESS=0
readonly EXIT_TIMEOUT=124
readonly EXIT_GENERAL_ERROR=1

# 偵測超時命令（跨平台相容）
# macOS 使用 gtimeout (brew install coreutils)
# Linux 使用 timeout
detect_timeout_command() {
    if command -v gtimeout >/dev/null 2>&1; then
        echo "gtimeout"
    elif command -v timeout >/dev/null 2>&1; then
        echo "timeout"
    else
        echo ""
    fi
}

readonly TIMEOUT_CMD=$(detect_timeout_command)

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 安全執行命令
# 用法: safe_execute [options] -- command [args...]
# 選項：
#   -t, --timeout SECONDS    超時時間（預設 5 秒）
#   -r, --record-failure     失敗時記錄到熔斷器
#   -s, --silent             靜默模式（不輸出錯誤）
#   -f, --fail-fast          失敗時立即返回錯誤碼（不靜默跳過）
#
# 返回：
#   0 - 成功或靜默跳過
#   非0 - 僅在 --fail-fast 時返回實際錯誤碼
safe_execute() {
    # 預設選項
    local timeout_seconds=$DEFAULT_TIMEOUT
    local record_failure=false
    local silent=false
    local fail_fast=false
    local command_args=()

    # 解析選項
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--timeout)
                timeout_seconds="$2"
                shift 2
                ;;
            -r|--record-failure)
                record_failure=true
                shift
                ;;
            -s|--silent)
                silent=true
                shift
                ;;
            -f|--fail-fast)
                fail_fast=true
                shift
                ;;
            --)
                shift
                command_args=("$@")
                break
                ;;
            *)
                echo "錯誤：無效的選項: $1" >&2
                echo "用法: safe_execute [options] -- command [args...]" >&2
                return $EXIT_GENERAL_ERROR
                ;;
        esac
    done

    # 檢查是否有命令
    if [ ${#command_args[@]} -eq 0 ]; then
        echo "錯誤：必須提供要執行的命令" >&2
        echo "用法: safe_execute [options] -- command [args...]" >&2
        return $EXIT_GENERAL_ERROR
    fi

    # 執行命令（根據是否有超時命令選擇執行方式）
    local exit_code=0
    local error_output=""

    if [ -n "$TIMEOUT_CMD" ]; then
        # 有超時命令：使用 timeout/gtimeout
        if [ "$silent" = true ]; then
            error_output=$("$TIMEOUT_CMD" "$timeout_seconds" "${command_args[@]}" 2>&1) || exit_code=$?
        else
            "$TIMEOUT_CMD" "$timeout_seconds" "${command_args[@]}" 2>&1 || exit_code=$?
        fi
    else
        # 無超時命令：直接執行（無法控制超時）
        if [ "$silent" = false ]; then
            echo "⚠️  警告：系統無 timeout 命令，無法控制超時（請安裝 coreutils）" >&2
        fi

        if [ "$silent" = true ]; then
            error_output=$("${command_args[@]}" 2>&1) || exit_code=$?
        else
            "${command_args[@]}" 2>&1 || exit_code=$?
        fi
    fi

    # 處理執行結果
    if [ $exit_code -eq 0 ]; then
        # 成功
        return $EXIT_SUCCESS
    fi

    # 失敗處理
    local failure_type="unknown"
    if [ $exit_code -eq $EXIT_TIMEOUT ]; then
        failure_type="timeout"
    else
        failure_type="error"
    fi

    # 輸出錯誤訊息（除非靜默模式）
    if [ "$silent" = false ]; then
        echo "⚠️  命令執行失敗 ($failure_type): ${command_args[*]}" >&2
        if [ -n "$error_output" ]; then
            echo "   錯誤輸出: $error_output" >&2
        fi
        echo "   退出碼: $exit_code" >&2
    fi

    # 記錄到熔斷器（如果啟用）
    if [ "$record_failure" = true ]; then
        record_failure 2>/dev/null || true
        if [ "$silent" = false ]; then
            echo "   已記錄到熔斷器" >&2
        fi
    fi

    # 返回錯誤碼（根據 fail-fast 模式）
    if [ "$fail_fast" = true ]; then
        return $exit_code
    else
        # 靜默跳過：返回成功
        return $EXIT_SUCCESS
    fi
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 檢查系統是否支援超時控制
# 用法: has_timeout_support
# 返回: 0=支援，1=不支援
has_timeout_support() {
    [ -n "$TIMEOUT_CMD" ]
}

# 顯示超時命令資訊
# 用法: show_timeout_info
show_timeout_info() {
    if has_timeout_support; then
        echo "✅ 超時控制已啟用: $TIMEOUT_CMD"
    else
        echo "⚠️  超時控制未啟用（請安裝 coreutils: brew install coreutils）"
    fi
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_help() {
    cat <<'EOF'
用法: safe_execute [options] -- command [args...]

選項:
  -t, --timeout SECONDS    超時時間（預設 5 秒）
  -r, --record-failure     失敗時記錄到熔斷器
  -s, --silent             靜默模式（不輸出錯誤）
  -f, --fail-fast          失敗時立即返回錯誤碼（不靜默跳過）

範例:
  # 基本用法：5 秒超時，失敗靜默跳過
  safe_execute -- ls /nonexistent

  # 自訂超時
  safe_execute -t 10 -- sleep 15

  # 失敗時記錄到熔斷器
  safe_execute -r -- risky_operation

  # 嚴格模式：失敗時返回錯誤
  safe_execute -f -- must_succeed_command

  # 靜默模式 + 記錄失敗
  safe_execute -s -r -- background_task

返回碼:
  0 - 成功或靜默跳過
  非0 - 僅在 --fail-fast 時返回實際錯誤碼
EOF
}

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        help|--help|-h|"")
            show_help
            exit 0
            ;;
        info)
            show_timeout_info
            exit 0
            ;;
        *)
            # 執行 safe_execute
            safe_execute "$@"
            exit $?
            ;;
    esac
fi
