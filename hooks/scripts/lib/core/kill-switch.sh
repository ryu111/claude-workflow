#!/bin/bash
# kill-switch.sh - 快速開關機制
# 功能：通過檔案存在性快速禁用記憶系統功能
# 邏輯：檔案存在 → 功能禁用（5 秒內生效）

set -euo pipefail

# 載入共用工具函式
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

readonly MEMORY_DIR="${PWD}/.claude/memory"
readonly KILL_SWITCH_DISABLED="${MEMORY_DIR}/.disabled"
readonly KILL_SWITCH_INJECT_DISABLED="${MEMORY_DIR}/.inject-disabled"
readonly KILL_SWITCH_READONLY="${MEMORY_DIR}/.readonly"

# 返回碼
readonly EXIT_NORMAL=0
readonly EXIT_DISABLED=1
readonly EXIT_INJECT_DISABLED=2
readonly EXIT_READONLY=3

# ═══════════════════════════════════════════════════════════════
# 核心功能 - 檢查開關狀態
# ═══════════════════════════════════════════════════════════════
# 注意：get_timestamp() 和 ensure_memory_dir() 已從 common.sh 載入

# 檢查記憶系統是否完全禁用
# 用法: is_memory_disabled
# 返回: 0=已禁用，1=未禁用
is_memory_disabled() {
    [ -f "$KILL_SWITCH_DISABLED" ]
}

# 檢查記憶注入是否禁用
# 用法: is_inject_disabled
# 返回: 0=已禁用，1=未禁用
is_inject_disabled() {
    [ -f "$KILL_SWITCH_INJECT_DISABLED" ]
}

# 檢查是否為只讀模式
# 用法: is_readonly_mode
# 返回: 0=只讀模式，1=非只讀模式
is_readonly_mode() {
    [ -f "$KILL_SWITCH_READONLY" ]
}

# 檢查所有快速開關
# 用法: check_kill_switches
# 返回: 0=正常，1=完全禁用，2=注入禁用，3=只讀模式
# 說明: 按優先級檢查，完全禁用 > 注入禁用 > 只讀模式
check_kill_switches() {
    if is_memory_disabled; then
        return $EXIT_DISABLED
    fi

    if is_inject_disabled; then
        return $EXIT_INJECT_DISABLED
    fi

    if is_readonly_mode; then
        return $EXIT_READONLY
    fi

    return $EXIT_NORMAL
}

# ═══════════════════════════════════════════════════════════════
# 核心功能 - 啟用/停用開關
# ═══════════════════════════════════════════════════════════════

# 啟用指定的快速開關
# 用法: enable_kill_switch <type>
# 參數: type - disabled | inject-disabled | readonly
# 返回: 0=成功，1=失敗
enable_kill_switch() {
    local switch_type="${1:-}"

    if [ -z "$switch_type" ]; then
        echo "錯誤：必須指定開關類型" >&2
        return 1
    fi

    ensure_memory_dir

    local switch_file
    local description

    case "$switch_type" in
        disabled)
            switch_file="$KILL_SWITCH_DISABLED"
            description="完全禁用記憶系統"
            ;;
        inject-disabled)
            switch_file="$KILL_SWITCH_INJECT_DISABLED"
            description="禁用記憶注入"
            ;;
        readonly)
            switch_file="$KILL_SWITCH_READONLY"
            description="只讀模式"
            ;;
        *)
            echo "錯誤：無效的開關類型: $switch_type" >&2
            echo "有效類型: disabled, inject-disabled, readonly" >&2
            return 1
            ;;
    esac

    if [ -f "$switch_file" ]; then
        echo "⚠️  開關已存在: $switch_type" >&2
        return 0
    fi

    local timestamp=$(get_timestamp)
    cat > "$switch_file" <<EOF
# Kill Switch: $description
# 建立時間: $timestamp
#
# 此檔案的存在表示功能已禁用
# 刪除此檔案即可恢復功能
EOF

    echo "✅ 已啟用開關: $switch_type ($description)" >&2
    return 0
}

# 停用指定的快速開關
# 用法: disable_kill_switch <type>
# 參數: type - disabled | inject-disabled | readonly
# 返回: 0=成功，1=失敗
disable_kill_switch() {
    local switch_type="${1:-}"

    if [ -z "$switch_type" ]; then
        echo "錯誤：必須指定開關類型" >&2
        return 1
    fi

    local switch_file
    local description

    case "$switch_type" in
        disabled)
            switch_file="$KILL_SWITCH_DISABLED"
            description="完全禁用記憶系統"
            ;;
        inject-disabled)
            switch_file="$KILL_SWITCH_INJECT_DISABLED"
            description="禁用記憶注入"
            ;;
        readonly)
            switch_file="$KILL_SWITCH_READONLY"
            description="只讀模式"
            ;;
        *)
            echo "錯誤：無效的開關類型: $switch_type" >&2
            echo "有效類型: disabled, inject-disabled, readonly" >&2
            return 1
            ;;
    esac

    if [ ! -f "$switch_file" ]; then
        echo "⚠️  開關不存在: $switch_type" >&2
        return 0
    fi

    rm -f "$switch_file"
    echo "✅ 已停用開關: $switch_type ($description)" >&2
    return 0
}

# ═══════════════════════════════════════════════════════════════
# 查詢功能
# ═══════════════════════════════════════════════════════════════

# 顯示所有開關狀態
# 用法: show_status
show_status() {
    echo "📊 Kill Switch 狀態報告"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 檢查完全禁用
    if is_memory_disabled; then
        echo "🔴 記憶系統: 完全禁用"
    else
        echo "🟢 記憶系統: 正常"
    fi

    # 檢查注入禁用
    if is_inject_disabled; then
        echo "🟡 記憶注入: 已禁用"
    else
        echo "🟢 記憶注入: 正常"
    fi

    # 檢查只讀模式
    if is_readonly_mode; then
        echo "🟡 寫入功能: 只讀模式"
    else
        echo "🟢 寫入功能: 正常"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 顯示檔案路徑
    echo ""
    echo "📁 開關檔案位置:"
    echo "  完全禁用: $KILL_SWITCH_DISABLED"
    echo "  注入禁用: $KILL_SWITCH_INJECT_DISABLED"
    echo "  只讀模式: $KILL_SWITCH_READONLY"
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_help() {
    cat <<EOF
用法: $0 <command> [options]

指令:
  check               檢查所有開關狀態（返回碼表示狀態）
  status              顯示所有開關狀態（人類可讀格式）
  enable <type>       啟用指定開關
  disable <type>      停用指定開關

開關類型:
  disabled            完全禁用記憶系統
  inject-disabled     只禁用記憶注入
  readonly            只讀模式（禁用寫入）

範例:
  # 檢查狀態（腳本中使用）
  $0 check
  echo \$?  # 0=正常, 1=完全禁用, 2=注入禁用, 3=只讀

  # 顯示狀態（人類可讀）
  $0 status

  # 啟用完全禁用
  $0 enable disabled

  # 停用完全禁用
  $0 disable disabled

  # 啟用只讀模式
  $0 enable readonly

返回碼:
  0 - 正常（check 指令）或操作成功
  1 - 完全禁用（check 指令）或操作失敗
  2 - 注入禁用（check 指令）
  3 - 只讀模式（check 指令）
EOF
}

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        check)
            check_kill_switches
            exit $?
            ;;
        status)
            show_status
            exit 0
            ;;
        enable)
            enable_kill_switch "${2:-}"
            exit $?
            ;;
        disable)
            disable_kill_switch "${2:-}"
            exit $?
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "錯誤：無效的指令 '${1:-}'" >&2
            echo "" >&2
            show_help
            exit 1
            ;;
    esac
fi
