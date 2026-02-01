#!/usr/bin/env bash
# memory-daily-backup.sh - 每日快照備份
# 功能：在 SessionEnd 時打包 MEMORY.md, daily/, experiences/ 到 .backups/daily/
# 邏輯：建立每日快照，保留最新 7 份，檢查今日是否已備份避免重複
# 觸發：SessionEnd hook 或手動執行
# 相容性：Bash 3.2+（macOS 預設版本）

# 注意：不使用 set -e，因為需要優雅處理錯誤
set -uo pipefail

# 載入依賴模組
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# 使用 Bash 3.2 相容的方式：先關閉 errexit，然後靜默載入
set +e  # 暫時關閉錯誤中斷
set +u  # 暫時關閉未定義變數檢查

# 載入模組（stderr 導向 /dev/null 忽略 readonly 警告）
. "${LIB_DIR}/core/common.sh" 2>/dev/null
. "${LIB_DIR}/core/circuit-breaker.sh" 2>/dev/null

# 注意：safe-execute.sh 通過直接複製函式邏輯避免載入衝突

# 恢復 set 選項
set -uo pipefail

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

readonly MEMORY_DIR="${PWD}/.claude/memory"
readonly DAILYBAK_DIR="${MEMORY_DIR}/.backups/daily"
readonly DAILYBAK_KEEP_COUNT=7

# 來源路徑
readonly SOURCE_MEMORY_FILE="${MEMORY_DIR}/MEMORY.md"
readonly SOURCE_DAILY_DIR="${MEMORY_DIR}/daily"
readonly SOURCE_EXPERIENCES_DIR="${MEMORY_DIR}/experiences"

# 返回碼
readonly DAILYBAK_EXIT_SUCCESS=0
readonly DAILYBAK_EXIT_FAILURE=1
readonly DAILYBAK_EXIT_SKIPPED=2

# ═══════════════════════════════════════════════════════════════
# 熔斷器與快速開關檢查
# ═══════════════════════════════════════════════════════════════

# 檢查是否應該執行（熔斷器 + 快速開關）
should_execute() {
    # 檢查熔斷器
    if bash "${LIB_DIR}/core/circuit-breaker.sh" is-open >/dev/null 2>&1; then
        echo "⚠️  記憶系統已禁用（熔斷器啟動），跳過每日備份" >&2
        return 1
    fi

    # 檢查快速開關（透過環境變數）
    if [ "${MEMORY_DAILY_BACKUP_DISABLED:-false}" = "true" ]; then
        echo "⚠️  每日備份已停用（快速開關），跳過執行" >&2
        return 1
    fi

    return 0
}

# ═══════════════════════════════════════════════════════════════
# 備份函式
# ═══════════════════════════════════════════════════════════════

# 建立今日快照
# 用法: create_daily_backup
# 返回: 0=成功，1=失敗，2=跳過（已存在）
create_daily_backup() {
    local today=$(date -u +%Y-%m-%d)
    local backup_dir="${DAILYBAK_DIR}/${today}"

    # 檢查是否已備份
    if [ -d "$backup_dir" ]; then
        echo "ℹ️  今日快照已存在: $backup_dir" >&2
        return $DAILYBAK_EXIT_SKIPPED
    fi

    # 確保備份根目錄存在
    if ! ensure_directory "$DAILYBAK_DIR"; then
        echo "❌ 無法建立備份目錄: $DAILYBAK_DIR" >&2
        return $DAILYBAK_EXIT_FAILURE
    fi

    # 建立今日快照目錄
    if ! mkdir -p "$backup_dir"; then
        echo "❌ 無法建立快照目錄: $backup_dir" >&2
        return $DAILYBAK_EXIT_FAILURE
    fi

    echo "📦 建立每日快照: $today" >&2

    # 收集要備份的檔案清單
    local -a backed_files=()
    local total_size=0

    # 1. 備份 MEMORY.md（如果存在）
    if [ -f "$SOURCE_MEMORY_FILE" ]; then
        if cp "$SOURCE_MEMORY_FILE" "$backup_dir/MEMORY.md" 2>/dev/null; then
            backed_files+=("MEMORY.md")
            local size=$(stat -f%z "$backup_dir/MEMORY.md" 2>/dev/null || stat -c%s "$backup_dir/MEMORY.md" 2>/dev/null || echo 0)
            total_size=$((total_size + size))
            echo "  ✓ 已備份: MEMORY.md (${size} bytes)" >&2
        fi
    fi

    # 2. 備份 daily/ 目錄（如果存在且有內容）
    if [ -d "$SOURCE_DAILY_DIR" ] && [ "$(ls -A "$SOURCE_DAILY_DIR" 2>/dev/null | grep -v '^\.gitkeep$' || true)" ]; then
        mkdir -p "$backup_dir/daily"
        cp -r "$SOURCE_DAILY_DIR"/* "$backup_dir/daily/" 2>/dev/null || true

        # 統計複製的檔案
        local daily_files=$(find "$backup_dir/daily" -type f ! -name '.gitkeep' 2>/dev/null | wc -l | tr -d ' ')
        if [ "$daily_files" -gt 0 ]; then
            for file in $(find "$backup_dir/daily" -type f ! -name '.gitkeep' 2>/dev/null); do
                local rel_path="daily/$(basename "$file")"
                backed_files+=("$rel_path")
                local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
                total_size=$((total_size + size))
            done
            echo "  ✓ 已備份: daily/ (${daily_files} 個檔案)" >&2
        fi
    fi

    # 3. 備份 experiences/ 目錄（如果存在且有內容）
    if [ -d "$SOURCE_EXPERIENCES_DIR" ] && [ "$(ls -A "$SOURCE_EXPERIENCES_DIR" 2>/dev/null | grep -v '^\.gitkeep$' || true)" ]; then
        mkdir -p "$backup_dir/experiences"
        cp -r "$SOURCE_EXPERIENCES_DIR"/* "$backup_dir/experiences/" 2>/dev/null || true

        # 統計複製的檔案
        local exp_files=$(find "$backup_dir/experiences" -type f ! -name '.gitkeep' 2>/dev/null | wc -l | tr -d ' ')
        if [ "$exp_files" -gt 0 ]; then
            for file in $(find "$backup_dir/experiences" -type f ! -name '.gitkeep' 2>/dev/null); do
                local rel_path="experiences/$(basename "$file")"
                backed_files+=("$rel_path")
                local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
                total_size=$((total_size + size))
            done
            echo "  ✓ 已備份: experiences/ (${exp_files} 個檔案)" >&2
        fi
    fi

    # 4. 建立 manifest.json
    create_manifest "$backup_dir" "$today" "${backed_files[@]}" "$total_size"

    echo "✅ 每日快照完成: $today (${total_size} bytes)" >&2
    return $DAILYBAK_EXIT_SUCCESS
}

# 建立 manifest.json
# 用法: create_manifest $backup_dir $date $files... $total_size
create_manifest() {
    local backup_dir="$1"
    local date="$2"
    shift 2

    # 最後一個參數是 total_size
    local -a files=("${@:1:$#-1}")
    local total_size="${@: -1}"

    local created=$(get_timestamp)
    local manifest_file="${backup_dir}/manifest.json"

    # 建立 JSON 陣列
    local files_json="["
    local first=true
    for file in "${files[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            files_json+=","
        fi
        files_json+="\"$file\""
    done
    files_json+="]"

    # 寫入 manifest
    cat > "$manifest_file" <<EOF
{
  "date": "$date",
  "created": "$created",
  "files": $files_json,
  "total_size": $total_size
}
EOF

    echo "  ✓ 已建立 manifest.json" >&2
}

# ═══════════════════════════════════════════════════════════════
# 查詢與清理函式
# ═══════════════════════════════════════════════════════════════

# 列出所有每日快照（按日期排序）
# 用法: list_daily_backups
# 輸出: 列印快照目錄列表
list_daily_backups() {
    if [ ! -d "$DAILYBAK_DIR" ]; then
        echo "ℹ️  備份目錄不存在: $DAILYBAK_DIR" >&2
        return $DAILYBAK_EXIT_SUCCESS
    fi

    local -a backups=($(find "$DAILYBAK_DIR" -maxdepth 1 -type d -name '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 2>/dev/null | sort -r || true))

    if [ ${#backups[@]} -eq 0 ]; then
        echo "ℹ️  無每日快照" >&2
        return $DAILYBAK_EXIT_SUCCESS
    fi

    echo "📋 每日快照列表 (共 ${#backups[@]} 份):" >&2
    for backup in "${backups[@]}"; do
        local date=$(basename "$backup")
        local manifest="${backup}/manifest.json"

        if [ -f "$manifest" ]; then
            local created=$(jq -r '.created // "unknown"' "$manifest" 2>/dev/null || echo "unknown")
            local total_size=$(jq -r '.total_size // 0' "$manifest" 2>/dev/null || echo 0)
            local file_count=$(jq -r '.files | length' "$manifest" 2>/dev/null || echo 0)
            echo "  • $date - $file_count 個檔案, ${total_size} bytes (建立於 $created)" >&2
        else
            echo "  • $date - (無 manifest)" >&2
        fi
    done

    return $DAILYBAK_EXIT_SUCCESS
}

# 清理舊的每日快照（保留最新 N 份）
# 用法: cleanup_old_daily_backups [$keep_count]
# 參數: $keep_count - 保留數量（預設 7）
cleanup_old_daily_backups() {
    local keep_count="${1:-$DAILYBAK_KEEP_COUNT}"

    if [ ! -d "$DAILYBAK_DIR" ]; then
        return $DAILYBAK_EXIT_SUCCESS
    fi

    # 取得所有快照（按日期排序，新到舊）
    local -a backups=($(find "$DAILYBAK_DIR" -maxdepth 1 -type d -name '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 2>/dev/null | sort -r || true))

    local total_count=${#backups[@]}
    if [ $total_count -le $keep_count ]; then
        echo "ℹ️  快照數量 ($total_count) 未超過保留數 ($keep_count)，無需清理" >&2
        return $DAILYBAK_EXIT_SUCCESS
    fi

    # 計算要刪除的數量
    local delete_count=$((total_count - keep_count))
    echo "🗑️  清理舊快照: 保留最新 $keep_count 份，刪除 $delete_count 份" >&2

    # 刪除舊快照（從最舊的開始）
    for ((i = keep_count; i < total_count; i++)); do
        local old_backup="${backups[$i]}"
        local date=$(basename "$old_backup")

        if rm -rf "$old_backup" 2>/dev/null; then
            echo "  ✓ 已刪除: $date" >&2
        else
            echo "  ⚠️  刪除失敗: $date" >&2
        fi
    done

    echo "✅ 清理完成" >&2
    return $DAILYBAK_EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# Hook 模式處理
# ═══════════════════════════════════════════════════════════════

# Hook 模式：從 stdin 讀取事件資料
handle_hook() {
    # 檢查是否應該執行
    if ! should_execute; then
        return $DAILYBAK_EXIT_SKIPPED
    fi

    # 讀取 stdin（雖然 SessionEnd 不一定需要資料）
    local input=""
    if [ -t 0 ]; then
        # 非 pipe 模式，無 stdin
        :
    else
        input=$(cat)
    fi

    # 執行備份
    local exit_code=0
    create_daily_backup || exit_code=$?

    # 根據結果執行清理
    if [ $exit_code -eq $DAILYBAK_EXIT_SUCCESS ]; then
        cleanup_old_daily_backups "$DAILYBAK_KEEP_COUNT"
    fi

    return $exit_code
}

# ═══════════════════════════════════════════════════════════════
# CLI 介面
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_help() {
    cat <<'EOF'
用法: memory-daily-backup.sh [command]

命令:
  hook                SessionEnd hook 模式（從 stdin 讀取事件）
  create              手動建立今日快照
  list                列出所有每日快照
  cleanup [N]         清理舊快照，保留最新 N 份（預設 7）
  help                顯示此說明

範例:
  # Hook 模式（通常由 SessionEnd 觸發）
  echo '{"session_id":"abc"}' | memory-daily-backup.sh hook

  # 手動建立快照
  memory-daily-backup.sh create

  # 列出所有快照
  memory-daily-backup.sh list

  # 清理舊快照（保留 5 份）
  memory-daily-backup.sh cleanup 5

環境變數:
  MEMORY_DAILY_BACKUP_DISABLED=true    停用每日備份

返回碼:
  0 - 成功
  1 - 失敗
  2 - 跳過（已存在或已禁用）
EOF
}

# ═══════════════════════════════════════════════════════════════
# 主程式入口
# ═══════════════════════════════════════════════════════════════

main() {
    local command="${1:-help}"

    case "$command" in
        hook)
            handle_hook
            ;;
        create)
            if ! should_execute; then
                exit $DAILYBAK_EXIT_SKIPPED
            fi
            create_daily_backup
            ;;
        list)
            list_daily_backups
            ;;
        cleanup)
            local keep_count="${2:-$DAILYBAK_KEEP_COUNT}"
            cleanup_old_daily_backups "$keep_count"
            ;;
        help|--help|-h)
            show_help
            exit $DAILYBAK_EXIT_SUCCESS
            ;;
        *)
            echo "❌ 未知命令: $command" >&2
            echo "" >&2
            show_help
            exit $DAILYBAK_EXIT_FAILURE
            ;;
    esac
}

# 執行主程式
main "$@"
