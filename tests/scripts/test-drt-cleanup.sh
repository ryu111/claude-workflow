#!/bin/bash
# test-drt-cleanup.sh - D→R→T 狀態清理邏輯測試
# 驗證: drt-state-cleanup.sh, migrate-drt-state.sh, loop-precheck.sh

echo "=== DRT 狀態清理邏輯測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLEANUP_SCRIPT="$PROJECT_ROOT/hooks/scripts/drt-state-cleanup.sh"
MIGRATE_SCRIPT="$PROJECT_ROOT/scripts/migrate-drt-state.sh"
PRECHECK_SCRIPT="$PROJECT_ROOT/hooks/scripts/loop-precheck.sh"

PASS=true
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# ========================================
# 測試 1: 腳本存在性檢查
# ========================================
echo "1. 測試腳本存在性..."

if [ ! -f "$CLEANUP_SCRIPT" ]; then
    echo "❌ drt-state-cleanup.sh 不存在"
    PASS=false
else
    echo "✅ drt-state-cleanup.sh 存在"
fi

if [ ! -f "$MIGRATE_SCRIPT" ]; then
    echo "❌ migrate-drt-state.sh 不存在"
    PASS=false
else
    echo "✅ migrate-drt-state.sh 存在"
fi

if [ ! -f "$PRECHECK_SCRIPT" ]; then
    echo "❌ loop-precheck.sh 不存在"
    PASS=false
else
    echo "✅ loop-precheck.sh 存在"
fi

# ========================================
# 測試 2: 語法檢查
# ========================================
echo ""
echo "2. 測試腳本語法..."

if bash -n "$CLEANUP_SCRIPT" 2>/dev/null; then
    echo "✅ drt-state-cleanup.sh 語法正確"
else
    echo "❌ drt-state-cleanup.sh 語法錯誤"
    PASS=false
fi

if bash -n "$MIGRATE_SCRIPT" 2>/dev/null; then
    echo "✅ migrate-drt-state.sh 語法正確"
else
    echo "❌ migrate-drt-state.sh 語法錯誤"
    PASS=false
fi

if bash -n "$PRECHECK_SCRIPT" 2>/dev/null; then
    echo "✅ loop-precheck.sh 語法正確"
else
    echo "❌ loop-precheck.sh 語法錯誤"
    PASS=false
fi

# ========================================
# 測試 3: 清理腳本功能測試（模擬環境）
# ========================================
echo ""
echo "3. 測試清理腳本功能..."

# 建立測試目錄結構
TEST_STATE_DIR="$TEMP_DIR/.drt-state"
TEST_STATE_AUTO_DIR="$TEMP_DIR/drt-state-auto"
mkdir -p "$TEST_STATE_DIR"
mkdir -p "$TEST_STATE_AUTO_DIR"

# 建立測試檔案
# 3.1 已完成的狀態檔案（應立即刪除）
echo '{"change_id":"test-001","result":"complete"}' > "$TEST_STATE_DIR/complete-001.json"
echo '{"change_id":"test-002","result":"pass"}' > "$TEST_STATE_AUTO_DIR/pass-001.json"

# 3.2 過期的檔案（使用 touch -t 模擬 3 天前）
# 格式: YYYYMMDDhhmm (4 天前)
if [ "$(uname)" = "Darwin" ]; then
    # macOS
    FOUR_DAYS_AGO=$(date -v-4d +"%Y%m%d%H%M")
else
    # Linux
    FOUR_DAYS_AGO=$(date -d "4 days ago" +"%Y%m%d%H%M")
fi

echo '{"change_id":"test-003","status":"in_progress"}' > "$TEST_STATE_DIR/old-001.json"
touch -t "$FOUR_DAYS_AGO" "$TEST_STATE_DIR/old-001.json"

# 3.3 正常的檔案（不應刪除）
echo '{"change_id":"test-004","status":"in_progress"}' > "$TEST_STATE_AUTO_DIR/normal-001.json"

# 執行清理腳本（在測試目錄下）
cd "$TEMP_DIR"
export PWD="$TEMP_DIR"

# 靜默執行清理
if bash "$CLEANUP_SCRIPT" > /dev/null 2>&1; then
    echo "✅ 清理腳本成功執行"

    # 驗證結果
    if [ ! -f "$TEST_STATE_DIR/complete-001.json" ]; then
        echo "✅ 已完成狀態檔案已刪除"
    else
        echo "❌ 已完成狀態檔案未刪除"
        PASS=false
    fi

    if [ ! -f "$TEST_STATE_AUTO_DIR/pass-001.json" ]; then
        echo "✅ PASS 狀態檔案已刪除"
    else
        echo "❌ PASS 狀態檔案未刪除"
        PASS=false
    fi

    if [ ! -f "$TEST_STATE_DIR/old-001.json" ]; then
        echo "✅ 過期檔案已刪除"
    else
        echo "❌ 過期檔案未刪除"
        PASS=false
    fi

    if [ -f "$TEST_STATE_AUTO_DIR/normal-001.json" ]; then
        echo "✅ 正常檔案未被刪除"
    else
        echo "❌ 正常檔案被錯誤刪除"
        PASS=false
    fi
else
    echo "❌ 清理腳本執行失敗"
    PASS=false
fi

# 回到專案根目錄
cd "$PROJECT_ROOT"

# ========================================
# 測試 4: 遷移腳本功能測試
# ========================================
echo ""
echo "4. 測試遷移腳本功能..."

# 建立測試目錄
TEST_MIGRATE_DIR="$TEMP_DIR/migrate-test"
mkdir -p "$TEST_MIGRATE_DIR/.claude"
mkdir -p "$TEST_MIGRATE_DIR/drt-state-auto"

# 建立舊格式的狀態檔案
echo '{"change_id":"migrate-001"}' > "$TEST_MIGRATE_DIR/.claude/.drt-state-migrate-001.json"
echo '{"change_id":"migrate-002"}' > "$TEST_MIGRATE_DIR/.claude/.drt-state-migrate-002.json"

# 執行 dry-run
cd "$TEST_MIGRATE_DIR"
if bash "$MIGRATE_SCRIPT" --dry-run > /dev/null 2>&1; then
    echo "✅ 遷移腳本 --dry-run 成功執行"

    # dry-run 不應實際移動檔案
    if [ -f ".claude/.drt-state-migrate-001.json" ]; then
        echo "✅ dry-run 未實際移動檔案"
    else
        echo "❌ dry-run 錯誤地移動了檔案"
        PASS=false
    fi
else
    echo "❌ 遷移腳本 --dry-run 執行失敗"
    PASS=false
fi

# 執行實際遷移（使用 --force 避免互動）
if bash "$MIGRATE_SCRIPT" --force > /dev/null 2>&1; then
    echo "✅ 遷移腳本實際執行成功"

    # 檢查檔案是否遷移
    if [ -f "drt-state-auto/migrate-001.json" ]; then
        echo "✅ 檔案成功遷移到新位置"
    else
        echo "❌ 檔案未遷移到新位置"
        PASS=false
    fi

    if [ ! -f ".claude/.drt-state-migrate-001.json" ]; then
        echo "✅ 舊檔案已移除"
    else
        echo "❌ 舊檔案未移除"
        PASS=false
    fi
else
    echo "❌ 遷移腳本實際執行失敗"
    PASS=false
fi

cd "$PROJECT_ROOT"

# ========================================
# 測試 5: 預檢腳本功能測試
# ========================================
echo ""
echo "5. 測試預檢腳本功能..."

# 建立測試環境
TEST_PRECHECK_DIR="$TEMP_DIR/precheck-test"
mkdir -p "$TEST_PRECHECK_DIR/.drt-state"
mkdir -p "$TEST_PRECHECK_DIR/drt-state-auto"
mkdir -p "$TEST_PRECHECK_DIR/openspec/changes/valid-change"
mkdir -p "$TEST_PRECHECK_DIR/openspec/archive/archived-change"

# 建立測試檔案
# 5.1 有效的狀態（對應 OpenSpec 存在且未完成）
echo '{"change_id":"valid-change"}' > "$TEST_PRECHECK_DIR/.drt-state/valid-change.json"
echo "- Status: IN_PROGRESS" > "$TEST_PRECHECK_DIR/openspec/changes/valid-change/tasks.md"

# 5.2 孤兒狀態（無對應 OpenSpec）
echo '{"change_id":"orphan-change"}' > "$TEST_PRECHECK_DIR/drt-state-auto/orphan-change.json"

# 5.3 已歸檔的狀態（OpenSpec 在 archive）
echo '{"change_id":"archived-change"}' > "$TEST_PRECHECK_DIR/.drt-state/archived-change.json"
echo "- Status: COMPLETED" > "$TEST_PRECHECK_DIR/openspec/archive/archived-change/tasks.md"

# 執行預檢
cd "$TEST_PRECHECK_DIR"
export PWD="$TEST_PRECHECK_DIR"

OUTPUT=$(bash "$PRECHECK_SCRIPT" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ 預檢腳本成功執行"

    # 檢查是否正確識別孤兒檔案
    if echo "$OUTPUT" | grep -q "孤兒.*2"; then
        echo "✅ 正確識別 2 個孤兒檔案"
    else
        echo "⚠️  孤兒檔案數量可能不正確"
    fi

    # 檢查是否正確識別有效檔案
    if echo "$OUTPUT" | grep -q "有效"; then
        echo "✅ 正確識別有效檔案"
    else
        echo "⚠️  未顯示有效檔案資訊"
    fi
else
    echo "❌ 預檢腳本執行失敗"
    PASS=false
fi

# 測試自動清理功能
OUTPUT_AUTO=$(bash "$PRECHECK_SCRIPT" --auto-clean 2>&1)
EXIT_CODE_AUTO=$?

if [ $EXIT_CODE_AUTO -eq 0 ]; then
    echo "✅ 預檢腳本 --auto-clean 成功執行"

    # 檢查孤兒檔案是否被刪除
    if [ ! -f "drt-state-auto/orphan-change.json" ]; then
        echo "✅ 孤兒檔案已被自動清理"
    else
        echo "❌ 孤兒檔案未被清理"
        PASS=false
    fi

    # 檢查有效檔案未被刪除
    if [ -f ".drt-state/valid-change.json" ]; then
        echo "✅ 有效檔案未被誤刪"
    else
        echo "❌ 有效檔案被錯誤刪除"
        PASS=false
    fi
else
    echo "❌ 預檢腳本 --auto-clean 執行失敗"
    PASS=false
fi

cd "$PROJECT_ROOT"

# ========================================
# 測試結果
# ========================================
echo ""
echo "────────────────────────────────────────"
if [ "$PASS" = true ]; then
    echo "✅ 所有 DRT 清理測試通過"
    exit 0
else
    echo "❌ DRT 清理測試失敗"
    exit 1
fi
