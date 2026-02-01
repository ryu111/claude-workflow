#!/bin/bash
# atomic-write.sh - 原子性檔案寫入工具函式庫
# 功能：提供原子性寫入、備份、驗證機制
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/atomic-write.sh"

set -euo pipefail

# 載入共用工具函式
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

readonly EXIT_SUCCESS=0
readonly EXIT_WRITE_FAILED=1
readonly EXIT_VERIFY_FAILED=2
readonly EXIT_LOCK_FAILED=3

readonly DEFAULT_PERMISSION="600"
readonly BACKUP_SUFFIX=".backup"

# ═══════════════════════════════════════════════════════════════
# 輔助函式
# ═══════════════════════════════════════════════════════════════

# 備份檔案
# 用法: backup_file "/path/to/file"
# 返回: 0=成功，1=失敗
backup_file() {
    local file_path="${1:-}"

    if [ -z "$file_path" ]; then
        echo "錯誤：backup_file 需要提供檔案路徑" >&2
        return 1
    fi

    if [ ! -f "$file_path" ]; then
        # 檔案不存在，無需備份
        return 0
    fi

    local backup_path="${file_path}${BACKUP_SUFFIX}.$(date +%s)"

    if ! cp "$file_path" "$backup_path" 2>/dev/null; then
        echo "錯誤：無法備份檔案: $file_path" >&2
        return 1
    fi

    return 0
}

# 驗證檔案內容（使用 sha256）
# 用法: verify_file "/path/to/file" "expected_content"
# 返回: 0=一致，1=不一致
verify_file() {
    local file_path="${1:-}"
    local expected_content="${2:-}"

    if [ -z "$file_path" ] || [ -z "$expected_content" ]; then
        echo "錯誤：verify_file 需要提供檔案路徑和預期內容" >&2
        return 1
    fi

    if [ ! -f "$file_path" ]; then
        echo "錯誤：檔案不存在: $file_path" >&2
        return 1
    fi

    # 計算預期內容的 sha256（echo 會自動加換行符，需一致）
    local expected_hash
    expected_hash=$(echo "$expected_content" | shasum -a 256 | awk '{print $1}')

    # 計算檔案實際內容的 sha256
    local actual_hash
    actual_hash=$(shasum -a 256 "$file_path" | awk '{print $1}')

    if [ "$expected_hash" != "$actual_hash" ]; then
        echo "錯誤：檔案內容驗證失敗" >&2
        echo "   預期 hash: $expected_hash" >&2
        echo "   實際 hash: $actual_hash" >&2
        return 1
    fi

    return 0
}

# ═══════════════════════════════════════════════════════════════
# 核心功能
# ═══════════════════════════════════════════════════════════════

# 原子性寫入檔案
# 用法: atomic_write [options] file_path content
# 選項：
#   -b, --backup         寫入前備份
#   -v, --verify         寫入後驗證 (sha256)
#   -p, --permission     檔案權限 (預設 600)
#   -l, --lock           使用檔案鎖定
#
# 返回：
#   0 - 成功
#   1 - 寫入失敗
#   2 - 驗證失敗
#   3 - 鎖定失敗
atomic_write() {
    # 預設選項
    local enable_backup=false
    local enable_verify=false
    local file_permission="$DEFAULT_PERMISSION"
    local enable_lock=false
    local file_path=""
    local content=""

    # 解析選項
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--backup)
                enable_backup=true
                shift
                ;;
            -v|--verify)
                enable_verify=true
                shift
                ;;
            -p|--permission)
                file_permission="$2"
                shift 2
                ;;
            -l|--lock)
                enable_lock=true
                shift
                ;;
            *)
                # 位置參數
                if [ -z "$file_path" ]; then
                    file_path="$1"
                elif [ -z "$content" ]; then
                    content="$1"
                else
                    echo "錯誤：未預期的參數: $1" >&2
                    return $EXIT_WRITE_FAILED
                fi
                shift
                ;;
        esac
    done

    # 驗證必要參數
    if [ -z "$file_path" ]; then
        echo "錯誤：atomic_write 需要提供檔案路徑" >&2
        echo "用法: atomic_write [options] file_path content" >&2
        return $EXIT_WRITE_FAILED
    fi

    # 注意：content 可以是空字串（合法情況）

    # 確保父目錄存在
    local parent_dir
    parent_dir="$(dirname "$file_path")"
    if ! ensure_directory "$parent_dir"; then
        return $EXIT_WRITE_FAILED
    fi

    # 備份（如果啟用）
    if [ "$enable_backup" = true ]; then
        if ! backup_file "$file_path"; then
            echo "錯誤：備份失敗，中止寫入" >&2
            return $EXIT_WRITE_FAILED
        fi
    fi

    # 原子寫入（使用 tmp + mv 模式）
    local temp_file="${file_path}.tmp.$$"

    # 寫入臨時檔案
    if ! echo "$content" > "$temp_file" 2>/dev/null; then
        echo "錯誤：無法寫入臨時檔案: $temp_file" >&2
        rm -f "$temp_file" 2>/dev/null || true
        return $EXIT_WRITE_FAILED
    fi

    # 設定檔案權限（在臨時檔案上）
    if ! chmod "$file_permission" "$temp_file" 2>/dev/null; then
        echo "錯誤：無法設定檔案權限: $file_permission" >&2
        rm -f "$temp_file" 2>/dev/null || true
        return $EXIT_WRITE_FAILED
    fi

    # 原子替換（mv 是原子操作）
    if ! mv "$temp_file" "$file_path" 2>/dev/null; then
        echo "錯誤：無法替換目標檔案: $file_path" >&2
        rm -f "$temp_file" 2>/dev/null || true
        return $EXIT_WRITE_FAILED
    fi

    # 驗證（如果啟用）
    if [ "$enable_verify" = true ]; then
        if ! verify_file "$file_path" "$content"; then
            echo "錯誤：檔案內容驗證失敗" >&2
            return $EXIT_VERIFY_FAILED
        fi
    fi

    # 檔案鎖定測試（如果啟用且 flock 可用）
    if [ "$enable_lock" = true ]; then
        if command -v flock &> /dev/null; then
            # 執行短暫的獨占鎖定測試
            if ! flock -x "$file_path" -c "cat \"$file_path\" > /dev/null" 2>/dev/null; then
                echo "錯誤：檔案鎖定測試失敗" >&2
                return $EXIT_LOCK_FAILED
            fi
        else
            echo "警告：flock 命令不可用，跳過鎖定測試" >&2
        fi
    fi

    return $EXIT_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 檢查系統是否支援檔案鎖定
# 用法: has_flock_support
# 返回: 0=支援，1=不支援
has_flock_support() {
    command -v flock &> /dev/null
}

# 顯示功能資訊
# 用法: show_atomic_write_info
show_atomic_write_info() {
    echo "原子性寫入工具資訊："
    echo "  預設檔案權限: $DEFAULT_PERMISSION"
    echo "  備份檔案後綴: $BACKUP_SUFFIX"

    if has_flock_support; then
        echo "  檔案鎖定支援: ✅ 已啟用"
    else
        echo "  檔案鎖定支援: ⚠️  未啟用（flock 命令不可用）"
    fi
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_help() {
    cat <<'EOF'
用法: atomic_write [options] file_path content

選項:
  -b, --backup         寫入前備份現有檔案
  -v, --verify         寫入後驗證內容 (sha256)
  -p, --permission     檔案權限 (預設 600)
  -l, --lock           使用檔案鎖定測試

範例:
  # 基本用法
  atomic_write /tmp/test.txt "Hello World"

  # 啟用所有功能
  atomic_write -b -v -l -p 644 /tmp/test.txt "Secure Content"

  # 僅備份和驗證
  atomic_write -b -v /tmp/state.json "{\"status\":\"ok\"}"

返回碼:
  0 - 成功
  1 - 寫入失敗
  2 - 驗證失敗
  3 - 鎖定失敗

功能:
  - 使用 tempfile + mv 確保原子性
  - 可選的自動備份機制
  - 可選的 sha256 內容驗證
  - 可選的檔案鎖定測試 (flock)
  - 強制檔案權限設定
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
            show_atomic_write_info
            exit 0
            ;;
        *)
            # 執行 atomic_write
            atomic_write "$@"
            exit $?
            ;;
    esac
fi
