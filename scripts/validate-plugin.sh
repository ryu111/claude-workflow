#!/bin/bash
# validate-plugin.sh - 驗證 plugin.json 配置和目錄結構
# 用法: ./validate-plugin.sh [plugin-dir]

set -e

# 載入共用函式庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/validate-utils.sh"

# 計算路徑
PLUGIN_DIR="${1:-$(dirname "$SCRIPT_DIR")}"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"

# 驗證結果變數
VALIDATIONS_PASSED=0
VALIDATIONS_FAILED=0
ERROR_MESSAGES=""

print_header "🔌 Plugin 配置驗證報告"
log_info "驗證路徑: $PLUGIN_DIR"

# ========================================
# 1. 檢查檔案存在
# ========================================
print_section "檔案檢查"

if check_file_exists "$PLUGIN_JSON"; then
    log_pass "plugin.json 存在"
    VALIDATIONS_PASSED=$((VALIDATIONS_PASSED + 1))
else
    log_fail "plugin.json 不存在: $PLUGIN_JSON"
    VALIDATIONS_FAILED=$((VALIDATIONS_FAILED + 1))
    ERROR_MESSAGES="$ERROR_MESSAGES\n- plugin.json 檔案不存在"
    print_final_status 1 "$ERROR_MESSAGES"
    exit 1
fi

# ========================================
# 2. 檢查 JSON 語法
# ========================================
print_section "JSON 語法驗證"

if jq empty "$PLUGIN_JSON" 2>/dev/null; then
    log_pass "JSON 語法正確"
    VALIDATIONS_PASSED=$((VALIDATIONS_PASSED + 1))
else
    log_fail "JSON 語法錯誤"
    VALIDATIONS_FAILED=$((VALIDATIONS_FAILED + 1))
    ERROR_MESSAGES="$ERROR_MESSAGES\n- JSON 語法錯誤，請檢查格式"
    print_final_status 1 "$ERROR_MESSAGES"
    exit 1
fi

# ========================================
# 3. 檢查必要欄位
# ========================================
print_section "必要欄位驗證"

REQUIRED_FIELDS=("name" "version" "description")
FIELDS_TABLE=""

for field in "${REQUIRED_FIELDS[@]}"; do
    field_value=$(jq -r ".$field" "$PLUGIN_JSON" 2>/dev/null || echo "null")

    if [ "$field_value" != "null" ] && [ -n "$field_value" ]; then
        log_pass "$field: $field_value"
        FIELDS_TABLE="$FIELDS_TABLE| $field | ✅ | \`$field_value\` |\n"
        VALIDATIONS_PASSED=$((VALIDATIONS_PASSED + 1))
    else
        log_fail "$field: 缺失或為空"
        FIELDS_TABLE="$FIELDS_TABLE| $field | ❌ | - |\n"
        VALIDATIONS_FAILED=$((VALIDATIONS_FAILED + 1))
        ERROR_MESSAGES="$ERROR_MESSAGES\n- 缺少必要欄位: $field"
    fi
done

# ========================================
# 4. 驗證版號格式 (Semantic Versioning)
# ========================================
print_section "版號格式驗證"

VERSION=$(jq -r ".version" "$PLUGIN_JSON" 2>/dev/null || echo "")

# Semantic Versioning 格式: MAJOR.MINOR.PATCH 或 MAJOR.MINOR.PATCH-prerelease
SEMVER_REGEX='^([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'

if [[ "$VERSION" =~ $SEMVER_REGEX ]]; then
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
    PRERELEASE="${BASH_REMATCH[4]}"

    log_pass "版號格式正確: $VERSION (MAJOR=$MAJOR, MINOR=$MINOR, PATCH=$PATCH)"
    if [ -n "$PRERELEASE" ]; then
        log_info "包含 Pre-release 標籤: $PRERELEASE"
    fi
    VALIDATIONS_PASSED=$((VALIDATIONS_PASSED + 1))
else
    log_fail "版號格式不符合 Semantic Versioning: $VERSION"
    log_info "正確格式範例: 1.0.0, 0.5.20, 2.1.3-beta.1"
    VALIDATIONS_FAILED=$((VALIDATIONS_FAILED + 1))
    ERROR_MESSAGES="$ERROR_MESSAGES\n- 版號格式不正確: $VERSION (應為 X.Y.Z 格式)"
fi

# ========================================
# 5. 檢查目錄結構
# ========================================
print_section "目錄結構驗證"

REQUIRED_DIRS=("agents" "skills" "commands" "hooks")
DIRS_TABLE=""

for dir in "${REQUIRED_DIRS[@]}"; do
    dir_path="$PLUGIN_DIR/$dir"

    if check_dir_exists "$dir_path"; then
        # 計算目錄內容數量
        if [ "$dir" = "agents" ]; then
            count=$(find "$dir_path" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
        elif [ "$dir" = "skills" ]; then
            count=$(find "$dir_path" -maxdepth 1 -type d ! -path "$dir_path" 2>/dev/null | wc -l | tr -d ' ')
        elif [ "$dir" = "commands" ]; then
            count=$(find "$dir_path" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
        elif [ "$dir" = "hooks" ]; then
            count=$(find "$dir_path/scripts" -maxdepth 1 -name "*.sh" -type f 2>/dev/null | wc -l | tr -d ' ' || echo 0)
        fi

        log_pass "$dir/ ($count 項目)"
        DIRS_TABLE="$DIRS_TABLE| $dir/ | ✅ | $count |\n"
        VALIDATIONS_PASSED=$((VALIDATIONS_PASSED + 1))
    else
        log_fail "$dir/ 目錄不存在"
        DIRS_TABLE="$DIRS_TABLE| $dir/ | ❌ | - |\n"
        VALIDATIONS_FAILED=$((VALIDATIONS_FAILED + 1))
        ERROR_MESSAGES="$ERROR_MESSAGES\n- 缺少必要目錄: $dir/"
    fi
done

# ========================================
# 6. 輸出詳細表格
# ========================================
echo ""
echo "### 欄位詳情"
echo "| 欄位 | 狀態 | 值 |"
echo "|------|:----:|-----|"
echo -e "$FIELDS_TABLE"

echo ""
echo "### 目錄詳情"
echo "| 目錄 | 狀態 | 項目數 |"
echo "|------|:----:|:------:|"
echo -e "$DIRS_TABLE"

# ========================================
# 7. 總結
# ========================================
print_section "總結"
TOTAL_VALIDATIONS=$((VALIDATIONS_PASSED + VALIDATIONS_FAILED))
echo "- 驗證項目總數：$TOTAL_VALIDATIONS"
echo "- 驗證通過：$VALIDATIONS_PASSED"
echo "- 驗證失敗：$VALIDATIONS_FAILED"

# 輸出最終狀態
if [ -n "$ERROR_MESSAGES" ]; then
    print_final_status "$VALIDATIONS_FAILED" "$ERROR_MESSAGES"
else
    print_final_status "$VALIDATIONS_FAILED"
fi
exit $?
