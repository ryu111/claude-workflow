#!/bin/bash
# memory-score.sh - 記憶評分系統
# 功能：計算記憶檔案的價值分數，用於優先級排序和容量管理
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-score.sh"

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 評分權重
readonly MEMSCORE_WEIGHT_ACCESS=10    # 存取次數權重
readonly MEMSCORE_WEIGHT_AGE=-1       # 年齡權重（負數，越舊越低分）
readonly MEMSCORE_WEIGHT_RELEVANCE=5  # 相關性權重
readonly MEMSCORE_RECENT_DAYS=7       # 最近使用的天數閾值

# 返回碼
readonly MEMSCORE_EXIT_SUCCESS=0
readonly MEMSCORE_EXIT_ERROR=1

# ═══════════════════════════════════════════════════════════════
# 載入依賴模組
# ═══════════════════════════════════════════════════════════════

# 安全取得腳本目錄
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    # 當被 source 時，使用當前目錄
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# 載入 YAML 解析工具
if [ -f "$SCRIPT_DIR/yaml-parser.sh" ]; then
    # shellcheck source=hooks/scripts/lib/yaml-parser.sh
    source "$SCRIPT_DIR/../core/yaml-parser.sh"
else
    echo "錯誤：找不到 yaml-parser.sh，SCRIPT_DIR=$SCRIPT_DIR" >&2
    # 不要立即退出，允許在交互模式下除錯
    [ "${BASH_SOURCE[0]:-}" = "${0:-}" ] && exit $MEMSCORE_EXIT_ERROR || return $MEMSCORE_EXIT_ERROR
fi

# ═══════════════════════════════════════════════════════════════
# 輔助函式
# ═══════════════════════════════════════════════════════════════

# 取得存取次數
# 用法: count=$(get_access_count "$memory_file")
# 輸出: 存取次數（從 frontmatter 提取 access_count）
# 返回: 0=成功，1=失敗
get_access_count() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ]; then
        echo "錯誤：get_access_count 需要提供檔案路徑" >&2
        return $MEMSCORE_EXIT_ERROR
    fi

    if [ ! -f "$memory_file" ]; then
        echo "錯誤：檔案不存在: $memory_file" >&2
        return $MEMSCORE_EXIT_ERROR
    fi

    # 使用 yaml-parser 提取 access_count
    local access_count
    access_count=$(parse_frontmatter "$memory_file" "access_count" 2>/dev/null) || {
        echo "0"  # 預設值
        return $MEMSCORE_EXIT_SUCCESS
    }

    # 確保是數字
    if [[ "$access_count" =~ ^[0-9]+$ ]]; then
        echo "$access_count"
    else
        echo "0"
    fi

    return $MEMSCORE_EXIT_SUCCESS
}

# 取得記憶年齡（天數）
# 用法: days=$(get_age_days "$memory_file")
# 輸出: 記憶年齡（天數，從 created 欄位計算）
# 返回: 0=成功，1=失敗
get_age_days() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ]; then
        echo "錯誤：get_age_days 需要提供檔案路徑" >&2
        return $MEMSCORE_EXIT_ERROR
    fi

    if [ ! -f "$memory_file" ]; then
        echo "錯誤：檔案不存在: $memory_file" >&2
        return $MEMSCORE_EXIT_ERROR
    fi

    # 使用 yaml-parser 提取 created 欄位
    local created_timestamp
    created_timestamp=$(parse_frontmatter "$memory_file" "created" 2>/dev/null) || {
        # 如果沒有 created 欄位，使用檔案修改時間
        if command -v stat >/dev/null 2>&1; then
            # macOS 和 Linux 的 stat 命令不同
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS
                local file_mtime
                file_mtime=$(stat -f %m "$memory_file" 2>/dev/null) || {
                    echo "0"
                    return $MEMSCORE_EXIT_SUCCESS
                }
            else
                # Linux
                local file_mtime
                file_mtime=$(stat -c %Y "$memory_file" 2>/dev/null) || {
                    echo "0"
                    return $MEMSCORE_EXIT_SUCCESS
                }
            fi

            local current_time
            current_time=$(date +%s)
            local age_seconds=$((current_time - file_mtime))
            local age_days=$((age_seconds / 86400))
            echo "$age_days"
            return $MEMSCORE_EXIT_SUCCESS
        fi

        echo "0"
        return $MEMSCORE_EXIT_SUCCESS
    }

    # 移除引號
    created_timestamp=$(echo "$created_timestamp" | sed 's/^["'\'']\(.*\)["'\'']$/\1/')

    # 解析 ISO 8601 時間戳（YYYY-MM-DDTHH:MM:SSZ）
    local created_epoch
    if command -v date >/dev/null 2>&1; then
        # 跨平台日期解析
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            created_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$created_timestamp" +%s 2>/dev/null) || {
                echo "0"
                return $MEMSCORE_EXIT_SUCCESS
            }
        else
            # Linux
            created_epoch=$(date -d "$created_timestamp" +%s 2>/dev/null) || {
                echo "0"
                return $MEMSCORE_EXIT_SUCCESS
            }
        fi

        local current_epoch
        current_epoch=$(date +%s)
        local age_seconds=$((current_epoch - created_epoch))
        local age_days=$((age_seconds / 86400))

        echo "$age_days"
    else
        echo "0"
    fi

    return $MEMSCORE_EXIT_SUCCESS
}

# 檢查是否最近使用過
# 用法: if is_recently_used "$memory_file" 7; then ...
# 參數: memory_file, days（預設 7）
# 返回: 0=最近使用過，1=否
is_recently_used() {
    local memory_file="${1:-}"
    local days="${2:-$MEMSCORE_RECENT_DAYS}"

    if [ -z "$memory_file" ]; then
        echo "錯誤：is_recently_used 需要提供檔案路徑" >&2
        return $MEMSCORE_EXIT_ERROR
    fi

    if [ ! -f "$memory_file" ]; then
        return $MEMSCORE_EXIT_ERROR
    fi

    # 檢查是否有 updated 欄位
    local updated_timestamp
    updated_timestamp=$(parse_frontmatter "$memory_file" "updated" 2>/dev/null) || {
        # 如果沒有 updated，檢查檔案修改時間
        if command -v stat >/dev/null 2>&1; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS
                local file_mtime
                file_mtime=$(stat -f %m "$memory_file" 2>/dev/null) || return $MEMSCORE_EXIT_ERROR
            else
                # Linux
                local file_mtime
                file_mtime=$(stat -c %Y "$memory_file" 2>/dev/null) || return $MEMSCORE_EXIT_ERROR
            fi

            local current_time
            current_time=$(date +%s)
            local age_seconds=$((current_time - file_mtime))
            local age_days=$((age_seconds / 86400))

            if [ "$age_days" -le "$days" ]; then
                return $MEMSCORE_EXIT_SUCCESS
            else
                return $MEMSCORE_EXIT_ERROR
            fi
        fi

        return $MEMSCORE_EXIT_ERROR
    }

    # 移除引號
    updated_timestamp=$(echo "$updated_timestamp" | sed 's/^["'\'']\(.*\)["'\'']$/\1/')

    # 解析時間戳
    local updated_epoch
    if command -v date >/dev/null 2>&1; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            updated_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$updated_timestamp" +%s 2>/dev/null) || return $MEMSCORE_EXIT_ERROR
        else
            # Linux
            updated_epoch=$(date -d "$updated_timestamp" +%s 2>/dev/null) || return $MEMSCORE_EXIT_ERROR
        fi

        local current_epoch
        current_epoch=$(date +%s)
        local age_seconds=$((current_epoch - updated_epoch))
        local age_days=$((age_seconds / 86400))

        if [ "$age_days" -le "$days" ]; then
            return $MEMSCORE_EXIT_SUCCESS
        else
            return $MEMSCORE_EXIT_ERROR
        fi
    fi

    return $MEMSCORE_EXIT_ERROR
}

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 計算記憶分數
# 用法: score=$(calculate_score "$memory_file")
# 參數: memory_file - 記憶檔案路徑（MEMORY.md 或 experiences/*.md）
# 輸出: 整數分數
# 返回: 0=成功，1=失敗
#
# 評分公式：
# score = access_count * 10 - age_days * 1 + relevance * 5 (如果最近 7 天使用過)
calculate_score() {
    local memory_file="${1:-}"

    if [ -z "$memory_file" ]; then
        echo "錯誤：calculate_score 需要提供檔案路徑" >&2
        return $MEMSCORE_EXIT_ERROR
    fi

    if [ ! -f "$memory_file" ]; then
        echo "錯誤：檔案不存在: $memory_file" >&2
        return $MEMSCORE_EXIT_ERROR
    fi

    # 取得存取次數
    local access_count
    access_count=$(get_access_count "$memory_file") || access_count=0

    # 取得年齡（天數）
    local age_days
    age_days=$(get_age_days "$memory_file") || age_days=0

    # 檢查是否最近使用過
    local relevance=0
    if is_recently_used "$memory_file" "$MEMSCORE_RECENT_DAYS"; then
        relevance=1
    fi

    # 計算分數
    local score
    score=$((access_count * MEMSCORE_WEIGHT_ACCESS + age_days * MEMSCORE_WEIGHT_AGE + relevance * MEMSCORE_WEIGHT_RELEVANCE))

    # 確保分數不為負
    if [ "$score" -lt 0 ]; then
        score=0
    fi

    echo "$score"
    return $MEMSCORE_EXIT_SUCCESS
}

# 列出所有記憶及分數
# 用法: list_memory_scores [memory_dir]
# 參數: memory_dir - 記憶目錄（預設 .claude/memory）
# 輸出: 格式化的記憶列表（分數由高到低）
list_memory_scores() {
    local memory_dir="${1:-.claude/memory}"

    if [ ! -d "$memory_dir" ]; then
        echo "錯誤：記憶目錄不存在: $memory_dir" >&2
        return $MEMSCORE_EXIT_ERROR
    fi

    # 建立臨時檔案存儲結果
    local temp_file
    temp_file=$(mktemp) || return $MEMSCORE_EXIT_ERROR

    # 掃描 MEMORY.md
    if [ -f "$memory_dir/MEMORY.md" ]; then
        local score
        score=$(calculate_score "$memory_dir/MEMORY.md" 2>/dev/null) || score=0
        printf "%d\t%s\n" "$score" "MEMORY.md" >> "$temp_file"
    fi

    # 掃描 experiences/*.md
    if [ -d "$memory_dir/experiences" ]; then
        find "$memory_dir/experiences" -type f -name "*.md" 2>/dev/null | while read -r exp_file; do
            local score
            score=$(calculate_score "$exp_file" 2>/dev/null) || score=0
            local rel_path="${exp_file#$memory_dir/}"
            printf "%d\t%s\n" "$score" "$rel_path" >> "$temp_file"
        done
    fi

    # 按分數排序並輸出
    if [ -s "$temp_file" ]; then
        echo "分數	檔案"
        echo "----	----"
        sort -rn "$temp_file" | while IFS=$'\t' read -r score file; do
            printf "%d\t%s\n" "$score" "$file"
        done
    fi

    rm -f "$temp_file"
    return $MEMSCORE_EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# CLI 介面
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_help() {
    cat <<'EOF'
記憶評分系統

用法:
  memory-score.sh score <file>     計算單一檔案分數
  memory-score.sh list [dir]       列出所有記憶及分數
  memory-score.sh help             顯示此說明

評分公式:
  score = access_count * 10 - age_days * 1 + relevance * 5

範例:
  # 計算單一檔案分數
  memory-score.sh score .claude/memory/MEMORY.md

  # 列出所有記憶及分數
  memory-score.sh list

  # 列出指定目錄的記憶分數
  memory-score.sh list /path/to/memory

返回碼:
  0 - 成功
  1 - 失敗
EOF
}

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-help}" in
        score)
            shift
            if [ $# -eq 0 ]; then
                echo "錯誤：需要提供檔案路徑" >&2
                show_help
                exit $MEMSCORE_EXIT_ERROR
            fi
            calculate_score "$@"
            exit $?
            ;;
        list)
            shift
            list_memory_scores "$@"
            exit $?
            ;;
        help|--help|-h|*)
            show_help
            exit $MEMSCORE_EXIT_SUCCESS
            ;;
    esac
fi
