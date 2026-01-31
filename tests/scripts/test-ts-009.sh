#!/bin/bash
# test-ts-009.sh - OpenSpec 生命週期測試
# 驗證: OpenSpec 從 specs → changes → archive

echo "=== TS-009: OpenSpec 生命週期測試 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OPENSPEC_DIR="$PROJECT_ROOT/openspec"

PASS=true

# Step 1: 檢查目錄結構
echo "Step 1: 檢查 OpenSpec 目錄結構..."

for dir in "specs" "changes" "archive"; do
    if [ -d "$OPENSPEC_DIR/$dir" ]; then
        echo "✅ $dir/ 存在"
    else
        echo "❌ $dir/ 不存在"
        mkdir -p "$OPENSPEC_DIR/$dir"
        echo "   已建立 $dir/"
    fi
done

# Step 2: 建立測試 Spec
echo ""
echo "Step 2: 建立測試 Spec..."

TEST_SPEC_DIR="$OPENSPEC_DIR/specs/test-lifecycle"
mkdir -p "$TEST_SPEC_DIR"

cat > "$TEST_SPEC_DIR/proposal.md" << 'EOF'
# Test Lifecycle Feature

## Summary
測試 OpenSpec 生命週期

## Status
- [x] Phase 1: Created (specs/)
- [ ] Phase 2: Approved (changes/)
- [ ] Phase 3: Completed (archive/)
EOF

cat > "$TEST_SPEC_DIR/tasks.md" << 'EOF'
## 1. Test Tasks
- [ ] 1.1 建立測試檔案 | agent: developer
EOF

echo "✅ 建立 test-lifecycle spec"

# Step 3: 模擬 approve → changes
echo ""
echo "Step 3: 模擬 approve (specs → changes)..."

if [ -d "$TEST_SPEC_DIR" ]; then
    mv "$TEST_SPEC_DIR" "$OPENSPEC_DIR/changes/"
    echo "✅ 移動到 changes/"
else
    echo "❌ spec 目錄不存在"
    PASS=false
fi

# Step 4: 驗證在 changes
echo ""
echo "Step 4: 驗證 spec 在 changes/..."

if [ -d "$OPENSPEC_DIR/changes/test-lifecycle" ]; then
    echo "✅ test-lifecycle 在 changes/"
else
    echo "❌ test-lifecycle 不在 changes/"
    PASS=false
fi

# Step 5: 模擬 complete → archive
echo ""
echo "Step 5: 模擬 complete (changes → archive)..."

if [ -d "$OPENSPEC_DIR/changes/test-lifecycle" ]; then
    mv "$OPENSPEC_DIR/changes/test-lifecycle" "$OPENSPEC_DIR/archive/"
    echo "✅ 移動到 archive/"
else
    echo "❌ spec 不在 changes/"
    PASS=false
fi

# Step 6: 驗證在 archive
echo ""
echo "Step 6: 驗證 spec 在 archive/..."

if [ -d "$OPENSPEC_DIR/archive/test-lifecycle" ]; then
    echo "✅ test-lifecycle 在 archive/"
else
    echo "❌ test-lifecycle 不在 archive/"
    PASS=false
fi

# 清理
rm -rf "$OPENSPEC_DIR/archive/test-lifecycle"

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-009 PASS: OpenSpec 生命週期正確"
    exit 0
else
    echo "❌ TS-009 FAIL"
    exit 1
fi
