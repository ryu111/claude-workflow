#!/usr/bin/env bash
# memory-isolation.sh - 記憶專案隔離工具
# 功能：確保記憶只在專案範圍內存取，防止跨專案記憶洩露
# 使用方式：source "$(dirname "${BASH_SOURCE[0]}")/lib/memory-isolation.sh"

set -euo pipefail

# 載入依賴
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/../core/common.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

# 返回碼
readonly ISOLATION_SUCCESS=0
readonly ISOLATION_ERROR=1
readonly ISOLATION_INVALID_PATH=2

# 記憶目錄常數
readonly MEMORY_SUBDIR=".claude/memory"
readonly GLOBAL_MEMORY_FLAG=".global-enabled"
readonly GLOBAL_MEMORY_DIR="${HOME}/.claude/memory"

# ═══════════════════════════════════════════════════════════════
# 專案根目錄偵測
# ═══════════════════════════════════════════════════════════════

# 取得專案根目錄
# 用法: project_root=$(get_project_root)
# 說明: 優先使用 PWD，若在 git repo 則使用 git root
# 輸出: 專案根目錄的絕對路徑
# 返回: 0=成功，1=失敗
get_project_root() {
    # 優先使用 PWD（當前工作目錄）
    if [ -n "${PWD:-}" ]; then
        # 轉換為絕對路徑（去除符號連結）
        if command -v realpath >/dev/null 2>&1; then
            realpath "$PWD" 2>/dev/null || echo "$PWD"
        else
            # macOS 相容性：使用 Python
            python3 -c "import os; print(os.path.realpath('$PWD'))" 2>/dev/null || echo "$PWD"
        fi
        return $ISOLATION_SUCCESS
    fi

    # 備用方案：使用 git root
    if git rev-parse --show-toplevel 2>/dev/null; then
        return $ISOLATION_SUCCESS
    fi

    echo "錯誤：無法偵測專案根目錄（PWD 未設定且不在 git repo）" >&2
    return $ISOLATION_ERROR
}

# ═══════════════════════════════════════════════════════════════
# 安全路徑驗證
# ═══════════════════════════════════════════════════════════════

# 解析並驗證安全路徑
# 用法: safe_path=$(resolve_safe_path "/path/to/file")
# 說明:
#   - 將路徑轉換為絕對路徑（去除符號連結）
#   - 驗證路徑是否在專案記憶目錄內
#   - 阻擋 .. 路徑穿越
# 參數: path - 要驗證的路徑
# 輸出: 安全的絕對路徑（若驗證通過）
# 返回: 0=安全，2=不安全
resolve_safe_path() {
    local input_path="${1:-}"

    if [ -z "$input_path" ]; then
        echo "錯誤：resolve_safe_path 需要提供路徑" >&2
        return $ISOLATION_INVALID_PATH
    fi

    # 取得專案記憶目錄
    local memory_dir
    if ! memory_dir=$(get_project_memory_dir); then
        return $ISOLATION_ERROR
    fi

    # 將輸入路徑轉換為絕對路徑
    local abs_path
    if [ -e "$input_path" ]; then
        # 檔案存在，使用 realpath 去除符號連結
        if command -v realpath >/dev/null 2>&1; then
            abs_path=$(realpath "$input_path" 2>/dev/null)
        else
            # macOS 相容性
            abs_path=$(python3 -c "import os; print(os.path.realpath('$input_path'))" 2>/dev/null)
        fi
    else
        # 檔案不存在，手動解析路徑
        # 如果是相對路徑，則相對於 memory_dir
        if [[ "$input_path" != /* ]]; then
            abs_path="${memory_dir}/${input_path}"
        else
            abs_path="$input_path"
        fi

        # 移除 .. 和 . 路徑組件（簡單實作）
        abs_path=$(echo "$abs_path" | sed 's|/\./|/|g')

        # 阻擋包含 .. 的路徑（防止路徑穿越）
        if echo "$abs_path" | grep -q '\.\.'; then
            echo "錯誤：路徑包含不安全的 '..' 組件: $input_path" >&2
            return $ISOLATION_INVALID_PATH
        fi
    fi

    # 驗證路徑是否在 memory_dir 內
    if ! validate_memory_path "$abs_path"; then
        return $ISOLATION_INVALID_PATH
    fi

    echo "$abs_path"
    return $ISOLATION_SUCCESS
}

# 驗證路徑是否在專案記憶目錄內
# 用法: validate_memory_path "/absolute/path/to/file"
# 說明: 檢查路徑是否在 {project}/.claude/memory/ 下
# 參數: path - 要驗證的絕對路徑
# 返回: 0=路徑安全，2=路徑不安全
validate_memory_path() {
    local path="${1:-}"

    if [ -z "$path" ]; then
        echo "錯誤：validate_memory_path 需要提供路徑" >&2
        return $ISOLATION_INVALID_PATH
    fi

    # 取得專案記憶目錄
    local memory_dir
    if ! memory_dir=$(get_project_memory_dir); then
        return $ISOLATION_ERROR
    fi

    # 檢查路徑是否以 memory_dir 開頭
    # 使用字串匹配（而非正則表達式）確保安全
    case "$path" in
        "$memory_dir"*)
            # 路徑在專案記憶目錄內
            return $ISOLATION_SUCCESS
            ;;
        *)
            # 檢查是否允許全域記憶
            if is_global_memory_enabled && [[ "$path" == "$GLOBAL_MEMORY_DIR"* ]]; then
                return $ISOLATION_SUCCESS
            fi

            echo "錯誤：路徑不在專案記憶目錄內: $path" >&2
            echo "  允許的目錄: $memory_dir" >&2
            return $ISOLATION_INVALID_PATH
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# 記憶目錄管理
# ═══════════════════════════════════════════════════════════════

# 取得專案記憶目錄
# 用法: memory_dir=$(get_project_memory_dir)
# 說明: 返回專案內的 .claude/memory/ 絕對路徑
# 輸出: 專案記憶目錄的絕對路徑
# 返回: 0=成功，1=失敗
get_project_memory_dir() {
    local project_root
    if ! project_root=$(get_project_root); then
        return $ISOLATION_ERROR
    fi

    # 組合記憶目錄路徑
    local memory_dir="${project_root}/${MEMORY_SUBDIR}"

    # 轉換為絕對路徑（去除符號連結）
    if [ -e "$memory_dir" ]; then
        if command -v realpath >/dev/null 2>&1; then
            realpath "$memory_dir" 2>/dev/null || echo "$memory_dir"
        else
            # macOS 相容性
            python3 -c "import os; print(os.path.realpath('$memory_dir'))" 2>/dev/null || echo "$memory_dir"
        fi
    else
        # 目錄不存在，返回規範化路徑
        echo "$memory_dir"
    fi

    return $ISOLATION_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 全域記憶管理
# ═══════════════════════════════════════════════════════════════

# 檢查是否啟用全域記憶
# 用法: is_global_memory_enabled
# 說明: 檢查 ~/.claude/memory/.global-enabled 是否存在
# 返回: 0=已啟用，1=未啟用
is_global_memory_enabled() {
    local flag_file="${GLOBAL_MEMORY_DIR}/${GLOBAL_MEMORY_FLAG}"

    if [ -f "$flag_file" ]; then
        return 0
    else
        return 1
    fi
}

# 啟用全域記憶
# 用法: enable_global_memory
# 說明: 建立 ~/.claude/memory/.global-enabled 檔案
# 返回: 0=成功，1=失敗
enable_global_memory() {
    local flag_file="${GLOBAL_MEMORY_DIR}/${GLOBAL_MEMORY_FLAG}"

    # 確保目錄存在
    if ! ensure_directory "$GLOBAL_MEMORY_DIR"; then
        echo "錯誤：無法建立全域記憶目錄" >&2
        return $ISOLATION_ERROR
    fi

    # 建立啟用檔案
    touch "$flag_file" || {
        echo "錯誤：無法建立全域記憶啟用檔案" >&2
        return $ISOLATION_ERROR
    }

    echo "已啟用全域記憶功能"
    return $ISOLATION_SUCCESS
}

# 禁用全域記憶
# 用法: disable_global_memory
# 說明: 移除 ~/.claude/memory/.global-enabled 檔案
# 返回: 0=成功，1=失敗
disable_global_memory() {
    local flag_file="${GLOBAL_MEMORY_DIR}/${GLOBAL_MEMORY_FLAG}"

    if [ -f "$flag_file" ]; then
        rm -f "$flag_file" || {
            echo "錯誤：無法移除全域記憶啟用檔案" >&2
            return $ISOLATION_ERROR
        }
        echo "已禁用全域記憶功能"
    else
        echo "全域記憶功能已處於禁用狀態"
    fi

    return $ISOLATION_SUCCESS
}

# ═══════════════════════════════════════════════════════════════
# 輔助功能
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_isolation_help() {
    cat <<'EOF'
記憶專案隔離工具 (Memory Isolation)

用法:
  source memory-isolation.sh

核心函式:
  get_project_root
    取得專案根目錄
    輸出: 專案根目錄的絕對路徑
    返回: 0=成功，1=失敗

  get_project_memory_dir
    取得專案記憶目錄
    輸出: 專案內 .claude/memory/ 的絕對路徑
    返回: 0=成功，1=失敗

  validate_memory_path <path>
    驗證路徑是否在專案記憶目錄內
    參數: path - 要驗證的絕對路徑
    返回: 0=路徑安全，2=路徑不安全

  resolve_safe_path <path>
    解析並驗證安全路徑
    參數: path - 要驗證的路徑（可為相對路徑）
    輸出: 安全的絕對路徑（若驗證通過）
    返回: 0=安全，2=不安全

全域記憶函式:
  is_global_memory_enabled
    檢查是否啟用全域記憶
    返回: 0=已啟用，1=未啟用

  enable_global_memory
    啟用全域記憶功能
    說明: 建立 ~/.claude/memory/.global-enabled
    返回: 0=成功，1=失敗

  disable_global_memory
    禁用全域記憶功能
    說明: 移除 ~/.claude/memory/.global-enabled
    返回: 0=成功，1=失敗

安全機制:
  - 使用 realpath 去除符號連結
  - 阻擋 .. 路徑穿越
  - 限制所有記憶存取在專案內 .claude/memory/
  - 支援可選的全域記憶（需明確啟用）

隔離邏輯:
  1. 取得專案根目錄（PWD 或 git root）
  2. 記憶路徑必須在 {project}/.claude/memory/ 下
  3. 使用 realpath 防止符號連結逃逸
  4. 禁止 .. 路徑穿越
  5. 若啟用全域記憶，允許讀取 ~/.claude/memory/

範例:
  # 取得專案記憶目錄
  memory_dir=$(get_project_memory_dir)
  echo "專案記憶目錄: $memory_dir"

  # 驗證路徑安全性
  if validate_memory_path "/path/to/file"; then
    echo "路徑安全"
  else
    echo "路徑不安全"
  fi

  # 解析並驗證路徑
  safe_path=$(resolve_safe_path "sessions/2024-01-01.jsonl")
  echo "安全路徑: $safe_path"

  # 檢查全域記憶
  if is_global_memory_enabled; then
    echo "全域記憶已啟用"
  fi

返回碼:
  0 - 成功
  1 - 一般錯誤
  2 - 路徑不安全

命令行介面 (CLI):
  bash memory-isolation.sh get-project-root
    顯示專案根目錄

  bash memory-isolation.sh get-memory-dir
    顯示專案記憶目錄

  bash memory-isolation.sh validate <path>
    驗證路徑是否安全

  bash memory-isolation.sh resolve <path>
    解析並驗證路徑

  bash memory-isolation.sh check-global
    檢查全域記憶狀態

  bash memory-isolation.sh enable-global
    啟用全域記憶

  bash memory-isolation.sh disable-global
    禁用全域記憶

  bash memory-isolation.sh help
    顯示此說明
EOF
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面（測試用）
# ═══════════════════════════════════════════════════════════════

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-}" in
        get-project-root)
            get_project_root
            exit $?
            ;;
        get-memory-dir)
            get_project_memory_dir
            exit $?
            ;;
        validate)
            if [ -z "${2:-}" ]; then
                echo "錯誤：需要提供路徑參數" >&2
                echo "用法: $0 validate <path>" >&2
                exit $ISOLATION_INVALID_PATH
            fi
            validate_memory_path "$2"
            exit $?
            ;;
        resolve)
            if [ -z "${2:-}" ]; then
                echo "錯誤：需要提供路徑參數" >&2
                echo "用法: $0 resolve <path>" >&2
                exit $ISOLATION_INVALID_PATH
            fi
            resolve_safe_path "$2"
            exit $?
            ;;
        check-global)
            if is_global_memory_enabled; then
                echo "全域記憶：已啟用"
                exit 0
            else
                echo "全域記憶：未啟用"
                exit 1
            fi
            ;;
        enable-global)
            enable_global_memory
            exit $?
            ;;
        disable-global)
            disable_global_memory
            exit $?
            ;;
        help|--help|-h|*)
            show_isolation_help
            exit 0
            ;;
    esac
fi
