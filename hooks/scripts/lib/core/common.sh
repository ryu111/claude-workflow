#!/bin/bash
# common.sh - 共用工具函式庫
# 功能：提供跨腳本使用的通用函式
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# ═══════════════════════════════════════════════════════════════
# 時間相關工具
# ═══════════════════════════════════════════════════════════════

# 取得當前時間戳（UTC，ISO 8601 格式）
# 用法: timestamp=$(get_timestamp)
# 輸出: 2024-01-01T10:30:00Z
get_timestamp() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# 取得當前 Unix 時間戳（秒）
# 用法: unix_time=$(get_unix_timestamp)
# 輸出: 1704106200
get_unix_timestamp() {
    date -u +%s
}

# ═══════════════════════════════════════════════════════════════
# 檔案系統工具
# ═══════════════════════════════════════════════════════════════

# 確保目錄存在（如果不存在則建立）
# 用法: ensure_directory "/path/to/dir"
# 返回: 0=成功（目錄已存在或成功建立），1=失敗
ensure_directory() {
    local dir_path="${1:-}"

    if [ -z "$dir_path" ]; then
        echo "錯誤：ensure_directory 需要提供目錄路徑" >&2
        return 1
    fi

    if [ ! -d "$dir_path" ]; then
        mkdir -p "$dir_path" || {
            echo "錯誤：無法建立目錄: $dir_path" >&2
            return 1
        }
    fi

    return 0
}

# 確保記憶系統目錄存在
# 用法: ensure_memory_dir
# 說明: 這是 ensure_directory 的便捷封裝，專門用於記憶系統
ensure_memory_dir() {
    local memory_dir="${PWD}/.claude/memory"
    ensure_directory "$memory_dir"
}
