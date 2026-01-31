#!/bin/bash
# migrate-drt-state.sh - DRT 狀態檔案遷移工具
# 功能: 將舊格式 .claude/.drt-state-* 遷移到 drt-state-auto/
# 用法: ./migrate-drt-state.sh [--dry-run] [--force]

set -e

# 載入共用函式庫
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/validate-utils.sh"

# 計算路徑
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLAUDE_DIR=".claude"
OLD_STATE_PATTERN="$CLAUDE_DIR/.drt-state-*.json"
NEW_STATE_DIR="drt-state-auto"

# 參數解析
DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force|-f)
            FORCE=true
            shift
            ;;
        *)
            echo "未知參數: $1"
            echo "用法: $0 [--dry-run] [--force]"
            exit 1
            ;;
    esac
done

# 計數器
TOTAL_FILES=0
MIGRATED_FILES=0
SKIPPED_FILES=0
FAILED_FILES=0

print_header "📦 DRT 狀態檔案遷移工具"

if [ "$DRY_RUN" = true ]; then
    log_warn "DRY RUN 模式 - 僅顯示將執行的操作，不會實際修改檔案"
    echo ""
fi

# 檢查 .claude 目錄是否存在
if ! check_dir_exists "$CLAUDE_DIR"; then
    log_fail ".claude 目錄不存在"
    exit 1
fi

# 建立新目錄（如果不存在）
if ! check_dir_exists "$NEW_STATE_DIR"; then
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$NEW_STATE_DIR"
        log_pass "建立目錄: $NEW_STATE_DIR/"
    else
        log_info "將建立目錄: $NEW_STATE_DIR/"
    fi
fi

# 尋找所有舊格式的狀態檔案
old_files=$(find "$CLAUDE_DIR" -maxdepth 1 -name ".drt-state-*.json" -type f 2>/dev/null || true)

if [ -z "$old_files" ]; then
    log_info "未找到需要遷移的檔案"
    echo ""
    echo "搜尋路徑: $CLAUDE_DIR/.drt-state-*.json"
    echo ""
    exit 0
fi

# 統計檔案數量
TOTAL_FILES=$(echo "$old_files" | wc -l | tr -d ' ')

print_section "遷移計劃"
echo ""
echo "找到 $TOTAL_FILES 個檔案需要遷移："
echo ""

# 顯示遷移計劃
for old_file in $old_files; do
    # 提取 change-id (移除 .claude/.drt-state- 前綴和 .json 後綴)
    basename_file=$(basename "$old_file")
    change_id="${basename_file#.drt-state-}"
    change_id="${change_id%.json}"

    new_file="$NEW_STATE_DIR/${change_id}.json"

    echo "  $old_file"
    echo "    → $new_file"
    echo ""
done

# 確認執行
if [ "$DRY_RUN" = false ] && [ "$FORCE" = false ]; then
    echo ""
    read -p "是否繼續遷移？[y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "遷移已取消"
        exit 0
    fi
    echo ""
fi

print_section "執行遷移"
echo ""

# 執行遷移
for old_file in $old_files; do
    # 提取 change-id
    basename_file=$(basename "$old_file")
    change_id="${basename_file#.drt-state-}"
    change_id="${change_id%.json}"

    new_file="$NEW_STATE_DIR/${change_id}.json"

    # 檢查目標檔案是否已存在
    if check_file_exists "$new_file"; then
        if [ "$FORCE" = false ]; then
            log_warn "跳過（目標已存在）: $change_id.json"
            SKIPPED_FILES=$((SKIPPED_FILES + 1))
            continue
        else
            log_warn "覆寫已存在的檔案: $change_id.json"
        fi
    fi

    # 執行遷移
    if [ "$DRY_RUN" = false ]; then
        if mv "$old_file" "$new_file" 2>/dev/null; then
            log_pass "遷移成功: $change_id.json"
            MIGRATED_FILES=$((MIGRATED_FILES + 1))
        else
            log_fail "遷移失敗: $basename_file"
            FAILED_FILES=$((FAILED_FILES + 1))
        fi
    else
        log_info "將遷移: $change_id.json"
        MIGRATED_FILES=$((MIGRATED_FILES + 1))
    fi
done

# 輸出報告
print_section "遷移報告"
echo "- 找到檔案數：$TOTAL_FILES"
echo "- 成功遷移：$MIGRATED_FILES"
if [ "$SKIPPED_FILES" -gt 0 ]; then
    echo "- 跳過檔案：$SKIPPED_FILES（目標已存在）"
fi
if [ "$FAILED_FILES" -gt 0 ]; then
    echo "- 失敗檔案：$FAILED_FILES"
fi

echo ""

if [ "$DRY_RUN" = true ]; then
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo -e "║              ${BLUE}ℹ️  DRY RUN 完成 - 未實際修改檔案${NC}              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "執行實際遷移請使用: $0"
    echo "強制覆寫已存在的檔案請使用: $0 --force"
elif [ "$FAILED_FILES" -gt 0 ]; then
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo -e "║              ${YELLOW}⚠️  遷移完成，但有部分失敗${NC}                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    exit 1
else
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo -e "║              ${GREEN}✅ 遷移成功完成${NC}                               ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
fi

echo ""
