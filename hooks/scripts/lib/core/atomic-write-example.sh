#!/bin/bash
# atomic-write-example.sh - 原子性寫入工具使用範例
# 展示如何在其他腳本中使用 atomic-write.sh

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 1. 載入函式庫
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/atomic-write.sh"

# ═══════════════════════════════════════════════════════════════
# 2. 基本使用範例
# ═══════════════════════════════════════════════════════════════

echo "=== 原子性寫入工具使用範例 ==="
echo ""

# 範例 1: 簡單寫入狀態檔案
echo "範例 1: 簡單寫入狀態檔案"
STATE_FILE="/tmp/example-state.json"
STATE_CONTENT='{"status":"running","timestamp":"2024-01-01T10:00:00Z"}'

atomic_write "$STATE_FILE" "$STATE_CONTENT"
echo "✅ 狀態檔案已寫入: $STATE_FILE"
echo ""

# 範例 2: 使用備份機制更新配置檔
echo "範例 2: 使用備份機制更新配置檔"
CONFIG_FILE="/tmp/example-config.yaml"
CONFIG_CONTENT="version: 1.0
enabled: true
settings:
  debug: false"

atomic_write -b "$CONFIG_FILE" "$CONFIG_CONTENT"
echo "✅ 配置檔已更新（已備份）: $CONFIG_FILE"
echo ""

# 範例 3: 高可靠性寫入（備份 + 驗證）
echo "範例 3: 高可靠性寫入（備份 + 驗證）"
CRITICAL_FILE="/tmp/example-critical.json"
CRITICAL_CONTENT='{"critical":true,"data":"important"}'

atomic_write -b -v "$CRITICAL_FILE" "$CRITICAL_CONTENT"
echo "✅ 關鍵檔案已安全寫入: $CRITICAL_FILE"
echo ""

# 範例 4: 自訂權限的敏感檔案
echo "範例 4: 自訂權限的敏感檔案"
SECRET_FILE="/tmp/example-secret.key"
SECRET_CONTENT="api_key=super_secret_12345"

atomic_write -p 600 "$SECRET_FILE" "$SECRET_CONTENT"
echo "✅ 敏感檔案已寫入（權限 600）: $SECRET_FILE"
echo ""

# 範例 5: 完整選項（備份 + 驗證 + 鎖定）
echo "範例 5: 完整選項（備份 + 驗證 + 鎖定）"
FULL_FILE="/tmp/example-full.json"
FULL_CONTENT='{"mode":"full","features":["backup","verify","lock"]}'

atomic_write -b -v -l "$FULL_FILE" "$FULL_CONTENT"
echo "✅ 檔案已寫入（完整保護）: $FULL_FILE"
echo ""

# ═══════════════════════════════════════════════════════════════
# 3. 實務應用範例
# ═══════════════════════════════════════════════════════════════

echo "=== 實務應用範例 ==="
echo ""

# 範例 6: DRT 工作流程狀態寫入（參考 workflow-gate.sh）
echo "範例 6: DRT 工作流程狀態寫入"
DRT_STATE_FILE="/tmp/example-drt-state.json"
AGENT_NAME="developer"
RESULT="complete"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

DRT_STATE=$(cat <<EOF
{
  "last_agent": "$AGENT_NAME",
  "result": "$RESULT",
  "timestamp": "$TIMESTAMP",
  "fail_count": 0,
  "reject_count": 0
}
EOF
)

atomic_write -v "$DRT_STATE_FILE" "$DRT_STATE"
echo "✅ DRT 狀態已更新: $DRT_STATE_FILE"
echo ""

# 範例 7: 錯誤處理
echo "範例 7: 錯誤處理"
ERROR_FILE="/invalid/path/example.txt"
ERROR_CONTENT="This will fail"

if atomic_write "$ERROR_FILE" "$ERROR_CONTENT" 2>/dev/null; then
    echo "✅ 寫入成功"
else
    EXIT_CODE=$?
    case $EXIT_CODE in
        1) echo "⚠️  錯誤: 寫入失敗" ;;
        2) echo "⚠️  錯誤: 驗證失敗" ;;
        3) echo "⚠️  錯誤: 鎖定失敗" ;;
        *) echo "⚠️  錯誤: 未知錯誤 (code: $EXIT_CODE)" ;;
    esac
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 4. 輔助函式使用範例
# ═══════════════════════════════════════════════════════════════

echo "=== 輔助函式使用範例 ==="
echo ""

# 範例 8: 檢查 flock 支援
echo "範例 8: 檢查 flock 支援"
if has_flock_support; then
    echo "✅ 系統支援 flock 檔案鎖定"
else
    echo "⚠️  系統不支援 flock（建議安裝）"
fi
echo ""

# 範例 9: 手動備份檔案
echo "範例 9: 手動備份檔案"
BACKUP_TARGET="/tmp/example-state.json"
if backup_file "$BACKUP_TARGET"; then
    echo "✅ 檔案已備份: $BACKUP_TARGET"
else
    echo "⚠️  備份失敗"
fi
echo ""

# 範例 10: 手動驗證檔案內容
echo "範例 10: 手動驗證檔案內容"
VERIFY_FILE="/tmp/example-state.json"
EXPECTED_CONTENT="$STATE_CONTENT"

if verify_file "$VERIFY_FILE" "$EXPECTED_CONTENT"; then
    echo "✅ 檔案內容驗證通過"
else
    echo "⚠️  檔案內容驗證失敗"
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# 5. 清理
# ═══════════════════════════════════════════════════════════════

echo "=== 清理範例檔案 ==="
rm -f /tmp/example-*.{json,yaml,key}
rm -f /tmp/example-*.backup.*
echo "✅ 清理完成"
echo ""

echo "=== 範例執行完畢 ==="
echo ""
echo "提示："
echo "  - 在 Hook 腳本中使用: source lib/atomic-write.sh"
echo "  - 關鍵狀態檔案建議使用: atomic_write -b -v"
echo "  - 敏感檔案建議使用: atomic_write -p 600"
