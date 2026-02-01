#!/bin/bash
# memory-health-check.sh - 記憶系統健康檢查與自動修復
# 功能：檢查記憶系統完整性，自動修復常見問題
# 邏輯：檢查目錄/檔案/權限/空間，失敗時嘗試修復並整合熔斷器

set -euo pipefail

# 載入依賴庫
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/../lib/core/common.sh"
source "${SCRIPT_DIR}/../lib/core/circuit-breaker.sh"

# ═══════════════════════════════════════════════════════════════
# 常數定義
# ═══════════════════════════════════════════════════════════════

readonly MEMORY_DIR="${PWD}/.claude/memory"
readonly CONFIG_FILE="${MEMORY_DIR}/config.yaml"
readonly MEMORY_FILE="${MEMORY_DIR}/MEMORY.md"
# HEALTH_FILE 已在 circuit-breaker.sh 定義，不重複定義

# 必要的子目錄
readonly REQUIRED_DIRS=(
    "${MEMORY_DIR}/daily"
    "${MEMORY_DIR}/sessions"
    "${MEMORY_DIR}/experiences"
    "${MEMORY_DIR}/.index"
    "${MEMORY_DIR}/.audit"
    "${MEMORY_DIR}/.backups"
    "${MEMORY_DIR}/.backups/instant"
    "${MEMORY_DIR}/.backups/daily"
)

# 必要的檔案
readonly REQUIRED_FILES=(
    "$CONFIG_FILE"
)

# 可選的檔案（存在則檢查）
readonly OPTIONAL_FILES=(
    "$MEMORY_FILE"
)

# 檔案權限要求
readonly REQUIRED_PERMISSIONS="600"

# 磁碟空間限制 (bytes)
readonly MAX_SIZE_BYTES=$((10 * 1024 * 1024))  # 10MB

# 返回碼
readonly EXIT_HEALTHY=0
readonly EXIT_FIXED=1
readonly EXIT_REPAIR_FAILED=2

# 健康檢查結果追蹤
declare -a HEALTH_ISSUES=()
declare -a HEALTH_FIXED=()
declare -a HEALTH_FAILED=()

# ═══════════════════════════════════════════════════════════════
# 工具函式
# ═══════════════════════════════════════════════════════════════

# 記錄問題
log_issue() {
    local message="$1"
    HEALTH_ISSUES+=("$message")
    echo "⚠️  問題: $message" >&2
}

# 記錄修復成功
log_fixed() {
    local message="$1"
    HEALTH_FIXED+=("$message")
    echo "✅ 已修復: $message" >&2
}

# 記錄修復失敗
log_failed() {
    local message="$1"
    HEALTH_FAILED+=("$message")
    echo "❌ 修復失敗: $message" >&2
}

# ═══════════════════════════════════════════════════════════════
# 檢查與修復函式
# ═══════════════════════════════════════════════════════════════

# 檢查並修復目錄結構
# 返回: 0=正常或已修復, 1=修復失敗
check_and_fix_directories() {
    local has_issues=0

    for dir in "${REQUIRED_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            log_issue "目錄不存在: $dir"
            has_issues=1

            # 嘗試修復
            if mkdir -p "$dir" 2>/dev/null; then
                log_fixed "已建立目錄: $dir"
            else
                log_failed "無法建立目錄: $dir"
                return 1
            fi
        fi
    done

    return 0
}

# 檢查並修復檔案
# 返回: 0=正常或已修復, 1=修復失敗
check_and_fix_files() {
    local has_issues=0

    # 檢查必要檔案
    for file in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "$file" ]; then
            log_issue "必要檔案不存在: $file"
            has_issues=1

            # 嘗試修復
            if restore_or_create_file "$file"; then
                log_fixed "已恢復檔案: $file"
            else
                log_failed "無法恢復檔案: $file"
                return 1
            fi
        fi
    done

    # 檢查可選檔案（僅驗證，不修復）
    for file in "${OPTIONAL_FILES[@]}"; do
        if [ -f "$file" ]; then
            # 驗證檔案完整性
            if ! validate_file_integrity "$file"; then
                log_issue "檔案可能損壞: $file"
                has_issues=1

                # 嘗試從備份恢復
                if restore_from_backup "$file"; then
                    log_fixed "已從備份恢復: $file"
                else
                    # 可選檔案無法恢復不算致命錯誤
                    echo "⚠️  無法恢復可選檔案: $file（可忽略）" >&2
                fi
            fi
        fi
    done

    return 0
}

# 檢查檔案權限
# 返回: 0=正常或已修復, 1=修復失敗
check_and_fix_permissions() {
    local has_issues=0
    local files_to_check=("${REQUIRED_FILES[@]}" "${OPTIONAL_FILES[@]}")

    for file in "${files_to_check[@]}"; do
        if [ -f "$file" ]; then
            local current_perm=$(stat -f "%Lp" "$file" 2>/dev/null || stat -c "%a" "$file" 2>/dev/null)

            if [ "$current_perm" != "$REQUIRED_PERMISSIONS" ]; then
                log_issue "檔案權限不符: $file (當前: $current_perm, 需要: $REQUIRED_PERMISSIONS)"
                has_issues=1

                # 嘗試修復
                if chmod "$REQUIRED_PERMISSIONS" "$file" 2>/dev/null; then
                    log_fixed "已修復權限: $file → $REQUIRED_PERMISSIONS"
                else
                    log_failed "無法修改權限: $file"
                    return 1
                fi
            fi
        fi
    done

    return 0
}

# 檢查磁碟使用量
# 返回: 0=正常, 1=超過限制（警告，不修復）
check_disk_usage() {
    if [ ! -d "$MEMORY_DIR" ]; then
        return 0  # 目錄不存在，跳過檢查
    fi

    # 計算目錄總大小（跨平台相容）
    local total_size
    if command -v du >/dev/null 2>&1; then
        # 使用 du -sk 計算大小（KB），然後轉換為 bytes
        total_size=$(du -sk "$MEMORY_DIR" 2>/dev/null | cut -f1)
        total_size=$((total_size * 1024))
    else
        # 備用方案：使用 find
        total_size=$(find "$MEMORY_DIR" -type f -exec stat -f "%z" {} \; 2>/dev/null | awk '{sum+=$1} END {print sum}')
    fi

    if [ "$total_size" -gt "$MAX_SIZE_BYTES" ]; then
        local size_mb=$((total_size / 1024 / 1024))
        local limit_mb=$((MAX_SIZE_BYTES / 1024 / 1024))
        log_issue "磁碟使用量超過限制: ${size_mb}MB / ${limit_mb}MB"
        echo "⚠️  建議執行清理：刪除舊的備份或日誌" >&2
        return 1
    fi

    return 0
}

# ═══════════════════════════════════════════════════════════════
# 修復輔助函式
# ═══════════════════════════════════════════════════════════════

# 驗證檔案完整性
# 返回: 0=正常, 1=可能損壞
validate_file_integrity() {
    local file="$1"

    # 基本檢查：檔案可讀且非空
    if [ ! -r "$file" ] || [ ! -s "$file" ]; then
        return 1
    fi

    # 根據檔案類型進行特定檢查
    case "$file" in
        *.yaml|*.yml)
            # YAML 檔案：檢查基本語法（簡單驗證）
            if ! grep -q "^[a-zA-Z_].*:" "$file" 2>/dev/null; then
                return 1
            fi
            ;;
        *.md)
            # Markdown 檔案：檢查是否為純文字
            if ! file "$file" 2>/dev/null | grep -q "text"; then
                return 1
            fi
            ;;
        *.json)
            # JSON 檔案：使用 jq 驗證（如果可用）
            if command -v jq >/dev/null 2>&1; then
                if ! jq -e '.' "$file" >/dev/null 2>&1; then
                    return 1
                fi
            fi
            ;;
    esac

    return 0
}

# 從備份恢復檔案
# 返回: 0=成功, 1=失敗
restore_from_backup() {
    local file="$1"
    local filename=$(basename "$file")

    # 尋找最新的備份
    local backup_dirs=(
        "${MEMORY_DIR}/.backups/instant"
        "${MEMORY_DIR}/.backups/daily"
    )

    for backup_dir in "${backup_dirs[@]}"; do
        if [ -d "$backup_dir" ]; then
            # 尋找最新的備份檔案
            local latest_backup=$(find "$backup_dir" -name "${filename}*" -type f 2>/dev/null | sort -r | head -1)

            if [ -n "$latest_backup" ] && [ -f "$latest_backup" ]; then
                # 驗證備份檔案
                if validate_file_integrity "$latest_backup"; then
                    cp "$latest_backup" "$file"
                    return 0
                fi
            fi
        fi
    done

    return 1
}

# 恢復或建立檔案
# 返回: 0=成功, 1=失敗
restore_or_create_file() {
    local file="$1"

    # 優先從備份恢復
    if restore_from_backup "$file"; then
        return 0
    fi

    # 無法從備份恢復，建立範本檔案
    case "$file" in
        */config.yaml)
            create_default_config
            return $?
            ;;
        */MEMORY.md)
            # MEMORY.md 是可選的，不建立
            return 1
            ;;
        *)
            # 其他檔案建立空檔案
            touch "$file" 2>/dev/null
            return $?
            ;;
    esac
}

# 建立預設配置檔
create_default_config() {
    local timestamp=$(get_timestamp)

    cat > "$CONFIG_FILE" <<'EOF'
# 持久記憶系統配置
# 版本: 1.0
#
# 此檔案控制記憶系統的漸進式發布階段
# Phase A → B → C：逐步啟用更多功能

version: "1.0"

# Rollout Phase 配置
# A: 只讀模式 - 最小風險，僅注入 MEMORY.md
# B: 有限寫入 - 顯式提取 + 基礎索引 + 用戶修正
# C: 全功能 - 隱式提取 + 動態注入 + 記憶衰退
rollout:
  phase: "A"  # A | B | C

  # 功能開關（根據 Phase 自動啟用）
  features:
    # ─── Phase A 功能（預設啟用）───
    inject_static: true              # 靜態注入 MEMORY.md

    # ─── Phase B 功能（需手動升級到 B）───
    extract_explicit: false          # 顯式提取（用戶說「記住」）
    index_basic: false               # 基礎索引（關鍵字搜尋）
    extract_correction: false        # 用戶修正提取（feedback loop）

    # ─── Phase C 功能（需手動升級到 C）───
    extract_implicit: false          # 隱式提取（Agent 完成後自動）
    inject_dynamic: false            # 動態注入（根據對話內容）
    decay: false                     # 記憶衰退（定期降低權重）

# Phase 升級指引
#
# 升級到 B:
#   1. 將 phase 改為 "B"
#   2. extract_explicit, index_basic, extract_correction 自動啟用
#   3. 觀察 1-2 週，確保穩定
#
# 升級到 C:
#   1. 將 phase 改為 "C"
#   2. extract_implicit, inject_dynamic, decay 自動啟用
#   3. 完整監控，確保無副作用
EOF

    if [ -f "$CONFIG_FILE" ]; then
        chmod "$REQUIRED_PERMISSIONS" "$CONFIG_FILE"
        return 0
    fi

    return 1
}

# ═══════════════════════════════════════════════════════════════
# 主要健康檢查流程
# ═══════════════════════════════════════════════════════════════

# 執行完整健康檢查
# 返回: 0=健康, 1=有問題但已修復, 2=修復失敗
run_health_check() {
    local has_issues=0
    local repair_failed=0

    echo "🏥 記憶系統健康檢查開始..." >&2
    echo "" >&2

    # 1. 檢查目錄結構
    echo "📁 檢查目錄結構..." >&2
    if ! check_and_fix_directories; then
        repair_failed=1
    fi
    echo "" >&2

    # 2. 檢查檔案
    echo "📄 檢查必要檔案..." >&2
    if ! check_and_fix_files; then
        repair_failed=1
    fi
    echo "" >&2

    # 3. 檢查權限
    echo "🔒 檢查檔案權限..." >&2
    if ! check_and_fix_permissions; then
        repair_failed=1
    fi
    echo "" >&2

    # 4. 檢查磁碟空間
    echo "💾 檢查磁碟使用量..." >&2
    if ! check_disk_usage; then
        # 磁碟空間超限不算致命錯誤
        has_issues=1
    fi
    echo "" >&2

    # 決定返回結果
    if [ "$repair_failed" -gt 0 ]; then
        # 有修復失敗，記錄到熔斷器
        record_failure
        print_health_report
        return $EXIT_REPAIR_FAILED
    elif [ "${#HEALTH_ISSUES[@]}" -gt 0 ] || [ "${#HEALTH_FIXED[@]}" -gt 0 ]; then
        # 有問題但都已修復
        print_health_report
        return $EXIT_FIXED
    else
        # 完全健康
        echo "✅ 記憶系統健康狀態良好" >&2
        return $EXIT_HEALTHY
    fi
}

# 輸出健康報告
print_health_report() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "📊 健康檢查報告" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2

    # 問題統計
    echo "發現問題: ${#HEALTH_ISSUES[@]}" >&2
    echo "已修復: ${#HEALTH_FIXED[@]}" >&2
    echo "修復失敗: ${#HEALTH_FAILED[@]}" >&2
    echo "" >&2

    # 詳細列表
    if [ "${#HEALTH_FAILED[@]}" -gt 0 ]; then
        echo "❌ 修復失敗的問題:" >&2
        for issue in "${HEALTH_FAILED[@]}"; do
            echo "   - $issue" >&2
        done
        echo "" >&2
    fi

    if [ "${#HEALTH_FIXED[@]}" -gt 0 ]; then
        echo "✅ 已修復的問題:" >&2
        for issue in "${HEALTH_FIXED[@]}"; do
            echo "   - $issue" >&2
        done
        echo "" >&2
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
}

# ═══════════════════════════════════════════════════════════════
# 命令行介面
# ═══════════════════════════════════════════════════════════════

# 顯示使用說明
show_help() {
    cat <<EOF
用法: $0 [command]

指令:
  run                執行完整健康檢查（預設）
  check-dirs         僅檢查目錄結構
  check-files        僅檢查檔案
  check-perms        僅檢查權限
  check-disk         僅檢查磁碟空間
  help               顯示此說明

返回碼:
  0 - 系統健康
  1 - 發現問題但已自動修復
  2 - 修復失敗（需人工介入）

範例:
  # 執行完整檢查
  $0 run

  # 僅檢查目錄
  $0 check-dirs

Hook 整合:
  此腳本設計用於 SessionStart Hook，自動檢查並修復記憶系統。
  修復失敗時會記錄到熔斷器，連續失敗會觸發保護機制。
EOF
}

# 當直接執行此腳本時提供 CLI
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
    case "${1:-run}" in
        run)
            run_health_check
            exit $?
            ;;
        check-dirs)
            check_and_fix_directories
            exit $?
            ;;
        check-files)
            check_and_fix_files
            exit $?
            ;;
        check-perms)
            check_and_fix_permissions
            exit $?
            ;;
        check-disk)
            check_disk_usage
            exit $?
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "錯誤：無效的指令 '${1}'" >&2
            echo "" >&2
            show_help
            exit 1
            ;;
    esac
fi
