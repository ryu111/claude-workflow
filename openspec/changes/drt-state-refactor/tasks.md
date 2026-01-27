## Progress
- Total: 6 tasks
- Completed: 6
- Status: COMPLETED

---

## 1. 準備階段 (sequential)
- [x] 1.1 建立 drt-state-auto 目錄和 .gitignore | agent: developer | files: drt-state-auto/, .gitignore
- [x] 1.2 定義狀態目錄常數和輔助函數 | agent: developer | files: hooks/scripts/workflow-gate.sh, hooks/scripts/subagent-validator.sh

## 2. 核心修改 (sequential, depends: 1)
- [x] 2.1 修改 workflow-gate.sh 寫入邏輯 | agent: developer | files: hooks/scripts/workflow-gate.sh
- [x] 2.2 修改 subagent-validator.sh 讀取邏輯 | agent: developer | files: hooks/scripts/subagent-validator.sh
- [x] 2.3 修改 session-cleanup-report.sh 清理邏輯 | agent: developer | files: hooks/scripts/session-cleanup-report.sh

## 3. 驗證與測試 (sequential, depends: 2)
- [x] 3.1 執行 D→R→T 流程測試，驗證狀態檔案正確性 | agent: tester | files: hooks/scripts/workflow-gate.sh, hooks/scripts/subagent-validator.sh

---

## 任務詳細說明

### 1.1 建立 drt-state-auto 目錄和 .gitignore

**目標**：建立專屬目錄並排除版本控制

**檢查清單**：
- 在專案根目錄建立 `drt-state-auto/` 資料夾
- 在 `.gitignore` 加入 `drt-state-auto/`
- 在 `drt-state-auto/` 加入 `.gitkeep` 確保目錄存在

### 1.2 定義狀態目錄常數和輔助函數

**目標**：統一狀態檔案路徑管理

**修改點**：
- 在 `workflow-gate.sh` 和 `subagent-validator.sh` 開頭定義：
  ```bash
  STATE_AUTO_DIR="${PWD}/drt-state-auto"
  mkdir -p "$STATE_AUTO_DIR" 2>/dev/null
  ```
- 修改 `get_state_file_path()` 函數（如果存在）或直接替換路徑變數

### 2.1 修改 workflow-gate.sh 寫入邏輯

**目標**：將狀態檔案寫入新位置

**修改位置**：
- 第 233-240 行：狀態檔案路徑決定邏輯
  ```bash
  # 修改前
  STATE_FILE="${STATE_DIR}/.drt-state-${CHANGE_ID}"

  # 修改後
  STATE_FILE="${STATE_AUTO_DIR}/${CHANGE_ID}.json"
  ```

**注意事項**：
- 保留 `STATE_DIR` 用於其他配置檔案
- 確保 `CHANGE_ID` 有效性檢查不變

### 2.2 修改 subagent-validator.sh 讀取邏輯

**目標**：從新位置讀取狀態檔案，並支援舊檔案 Fallback

**修改位置**：
- 第 133-138 行：狀態檔案路徑決定邏輯
  ```bash
  # 修改後（新位置 + Fallback）
  STATE_FILE="${STATE_AUTO_DIR}/${CHANGE_ID}.json"

  # Fallback: 如果新位置沒有，檢查舊位置
  if [ ! -f "$STATE_FILE" ]; then
      OLD_STATE_FILE="${STATE_DIR}/.drt-state-${CHANGE_ID}"
      if [ -f "$OLD_STATE_FILE" ]; then
          STATE_FILE="$OLD_STATE_FILE"
          echo "[$(date)] Fallback to old state file: $OLD_STATE_FILE" >> "$DEBUG_LOG"
      fi
  fi
  ```

**向後相容**：
- 優先讀取新位置 `drt-state-auto/${CHANGE_ID}.json`
- 如果不存在，嘗試舊位置 `.claude/.drt-state-${CHANGE_ID}`
- 寫入時只使用新位置

### 2.3 修改 session-cleanup-report.sh 清理邏輯

**目標**：清理新位置的過期檔案，保留時間改為 1 天

**修改位置**：
- 第 70-88 行：清理邏輯
  ```bash
  # 修改後
  STATE_AUTO_DIR="${PWD}/drt-state-auto"
  if [ -d "$STATE_AUTO_DIR" ]; then
      CLEANED_COUNT=0
      if command -v find &> /dev/null; then
          # 清理超過 1 天的檔案（原本是 7 天）
          CLEANED_FILES=$(find "$STATE_AUTO_DIR" -name "*.json" -type f -mtime +1 2>/dev/null)
          if [ -n "$CLEANED_FILES" ]; then
              CLEANED_COUNT=$(echo "$CLEANED_FILES" | wc -l | tr -d ' ')
              echo "$CLEANED_FILES" | xargs rm -f 2>/dev/null
          fi
      fi

      if [ "$CLEANED_COUNT" -gt 0 ]; then
          echo "🧹 清理舊狀態檔案: $CLEANED_COUNT 個（超過 1 天）"
          echo ""
      fi
  fi

  # 同時清理舊位置的檔案（遷移期間）
  STATE_DIR="${PWD}/.claude"
  if [ -d "$STATE_DIR" ]; then
      OLD_CLEANED=$(find "$STATE_DIR" -name ".drt-state-auto-*" -type f -mtime +1 2>/dev/null | wc -l | tr -d ' ')
      if [ "$OLD_CLEANED" -gt 0 ]; then
          find "$STATE_DIR" -name ".drt-state-auto-*" -type f -mtime +1 -delete 2>/dev/null
          echo "🧹 清理舊位置狀態檔案: $OLD_CLEANED 個"
      fi
  fi
  ```

**變更重點**：
- 保留時間從 `+7` 改為 `+1`
- 掃描新目錄 `drt-state-auto/*.json`
- 同時清理舊位置檔案（遷移期）

### 3.1 執行 D→R→T 流程測試

**測試場景**：

1. **新狀態檔案建立測試**
   - 啟動 DEVELOPER → 檢查 `drt-state-auto/` 下是否有新檔案
   - 檔案格式：`{change_id}.json`

2. **舊檔案 Fallback 測試**
   - 手動建立舊格式檔案 `.claude/.drt-state-test-12345`
   - 啟動 REVIEWER → 驗證可正確讀取舊檔案
   - 寫入時應使用新位置

3. **清理邏輯測試**
   - 建立 2 天前的測試檔案
   - 執行 `bash hooks/scripts/session-cleanup-report.sh < /dev/null`
   - 驗證檔案被清理

4. **競態條件測試**
   - 在清理過程中寫入新檔案
   - 驗證新檔案不被誤刪

**預期結果**：
- ✅ 新檔案寫入 `drt-state-auto/` 目錄
- ✅ 舊檔案可正確讀取（Fallback）
- ✅ 1 天後舊檔案被清理
- ✅ 清理不影響有效檔案（< 30 分鐘）
- ✅ 通過 D→R→T 流程（DEVELOPER → REVIEWER → TESTER）

---

## 執行順序說明

**Phase 1（準備階段）**：必須依序執行
- 先建立目錄結構（1.1）
- 再定義常數和函數（1.2）

**Phase 2（核心修改）**：必須依序執行
- 先改寫入（2.1）
- 再改讀取（2.2，包含 Fallback）
- 最後改清理（2.3）

**Phase 3（驗證與測試）**：等待 Phase 2 全部完成後執行
- 完整的 D→R→T 流程測試
- 向後相容性驗證
- 清理邏輯驗證

---

## 注意事項

### 禁止硬編碼

所有路徑和時間常數使用變數：
```bash
readonly STATE_AUTO_DIR="${PWD}/drt-state-auto"
readonly CLEANUP_DAYS=1  # 清理閾值
```

### 原子寫入

使用現有的 `atomic_write_state()` 函數，確保並行安全。

### 日誌記錄

所有關鍵操作記錄到 `/tmp/claude-workflow-debug.log`：
```bash
echo "[$(date)] State file path: $STATE_FILE" >> "$DEBUG_LOG"
```

### 錯誤處理

目錄建立失敗時優雅降級：
```bash
mkdir -p "$STATE_AUTO_DIR" 2>/dev/null || {
    echo "⚠️ 無法建立 drt-state-auto/ 目錄，使用預設位置" >&2
    STATE_AUTO_DIR="$STATE_DIR"
}
```
