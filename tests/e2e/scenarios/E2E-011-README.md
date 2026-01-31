# E2E-011: UserPromptSubmit Hook 觸發測試

## 概述

此測試場景驗證 `keyword-detector.sh` (UserPromptSubmit Hook) 的功能，確保關鍵字檢測、範本注入、優先級排序等機制正常運作。

## 測試範圍

### 核心功能

1. **關鍵字檢測**
   - 中文關鍵字：「規劃」、「設計」、「loop」
   - 英文關鍵字：「architect」、「designer」、「resume」
   - 大小寫不敏感

2. **範本注入**
   - 載入正確的範本檔案（`hooks/templates/*.md`）
   - 變數替換：`{{PROMPT}}` → 用戶實際輸入
   - 範本優先級：用戶自訂 > 預設範本

3. **優先級排序**
   - 當多個關鍵字同時匹配時，選擇優先級最高的
   - 優先級順序：ARCHITECT(1) > DESIGNER(2) > RESUME(3) > LOOP(4) > ...

4. **JSON 輸出格式**
   - 有效的 JSON 格式
   - 必要欄位：`hookSpecificOutput.hookEventName`, `hookSpecificOutput.additionalContext`
   - hookEventName 固定為 `UserPromptSubmit`

5. **邊界情況**
   - 空字串輸入
   - 無匹配關鍵字
   - 特殊字元處理

## 測試場景

| 場景 | 輸入 | 預期輸出 | 驗證項目 |
|------|------|----------|----------|
| 1 | 「規劃一個計數器功能」 | ARCHITECT 提示 | 關鍵字檢測、範本載入 |
| 2 | 「loop」 | LOOP 提示 | 關鍵字檢測、tasks.md 說明 |
| 3 | 「這是什麼專案？」 | 空字串 | 無匹配時不注入 |
| 4 | 「規劃並設計用戶介面」 | ARCHITECT 提示（非 DESIGNER） | 優先級排序 |
| 5 | 「LOOP」 | LOOP 提示 | 大小寫不敏感 |
| 6 | 空字串 | 空字串 | 空輸入處理 |
| 7 | 「規劃功能」 | 有效 JSON | JSON 格式驗證 |
| 8 | 「規劃計數器功能」 | 包含原始 prompt | 變數替換 |

## 執行方式

### 方式 1：使用 E2E Runner

```bash
# 執行 E2E-011 場景
bash tests/e2e/e2e-runner.sh E2E-011

# 執行並生成報告
bash tests/e2e/e2e-runner.sh E2E-011 --report
```

### 方式 2：使用獨立測試腳本（推薦）

```bash
# 執行完整測試套件（8 個測試）
bash tests/e2e/scenarios/run-E2E-011.sh
```

### 方式 3：手動測試單一場景

```bash
# 設定環境變數
export CLAUDE_PLUGIN_ROOT="/Users/sbu/projects/claude-workflow"

# 測試規劃指令
echo '{"userPrompt":"規劃一個計數器功能"}' | \
  bash hooks/scripts/keyword-detector.sh | jq

# 測試 loop 指令
echo '{"userPrompt":"loop"}' | \
  bash hooks/scripts/keyword-detector.sh | jq

# 測試無匹配
echo '{"userPrompt":"這是什麼專案？"}' | \
  bash hooks/scripts/keyword-detector.sh | jq
```

## 成功標準

測試被視為成功需滿足以下條件：

- ✅ 所有 8 個測試場景通過
- ✅ 合規率 >= 90%（E2E Runner）
- ✅ 無未修復違規
- ✅ JSON 格式正確
- ✅ 關鍵字檢測準確
- ✅ 優先級排序正確

## 預期成功率

- **目標成功率**: 100%
- **可接受成功率**: >= 95%

## 測試輸出範例

### 成功輸出

```
╔════════════════════════════════════════════════════════════════╗
║           E2E-011: UserPromptSubmit Hook 測試套件              ║
╚════════════════════════════════════════════════════════════════╝

🧪 測試 1/8：規劃指令觸發 ARCHITECT
✅ 場景 1 通過：偵測到 ARCHITECT 提示

🧪 測試 2/8：loop 指令觸發
✅ 場景 2 通過：偵測到 loop 提示

...（其他測試）...

═══════════════════════════════════════════════════════════════

測試結果摘要

  總計：8 個測試
  通過：8
  失敗：0

✅ E2E-011 測試完全通過

  驗證項目：
    ✓ 關鍵字檢測
    ✓ 範本載入
    ✓ 變數替換
    ✓ 優先級排序
    ✓ JSON 格式
    ✓ 大小寫處理
    ✓ 空字串處理
```

## 相關檔案

| 檔案 | 用途 |
|------|------|
| `E2E-011-userprompt-trigger.yaml` | 測試場景定義 |
| `run-E2E-011.sh` | 獨立測試執行腳本 |
| `E2E-011-README.md` | 本文檔 |
| `hooks/scripts/keyword-detector.sh` | 被測試的 Hook 腳本 |
| `hooks/templates/*.md` | 範本檔案 |

## 除錯資訊

### Debug Log 位置

```bash
tail -f /tmp/claude-workflow-debug.log
```

### 常見問題

#### 1. 找不到範本檔案

**問題**: 測試失敗，錯誤訊息為「No accessible template found」

**解決方案**:
```bash
# 確認 CLAUDE_PLUGIN_ROOT 正確設定
echo $CLAUDE_PLUGIN_ROOT

# 驗證範本檔案存在
ls -la hooks/templates/

# 檢查權限
chmod +r hooks/templates/*.md
```

#### 2. JSON 解析失敗

**問題**: `jq` 命令失敗或輸出格式錯誤

**解決方案**:
```bash
# 安裝 jq（如果未安裝）
brew install jq  # macOS
sudo apt install jq  # Ubuntu/Debian

# 驗證 JSON 輸出
echo '{"userPrompt":"test"}' | \
  bash hooks/scripts/keyword-detector.sh | jq empty
```

#### 3. 關鍵字未被檢測

**問題**: 輸入包含關鍵字但未觸發

**檢查項目**:
- 英文關鍵字是否有 word boundary（空格或標點）
- 檢查 debug log 確認關鍵字映射
- 驗證大小寫轉換是否正常

## 維護指南

### 新增測試場景

1. 編輯 `E2E-011-userprompt-trigger.yaml`
2. 在 `test_cases` 區塊新增場景
3. 在 `run-E2E-011.sh` 新增對應測試
4. 更新 `TOTAL_TESTS` 變數
5. 執行測試驗證

### 新增關鍵字

當新增關鍵字映射時：

1. 更新 `keyword-detector.sh` 中的 `KEYWORD_MAPPINGS`
2. 建立對應的範本檔案（`hooks/templates/*.md`）
3. 在 E2E-011 新增測試案例
4. 更新本文檔的測試範圍

## 版本歷史

| 版本 | 日期 | 變更內容 |
|------|------|----------|
| 1.0.0 | 2026-01-27 | 初始版本，8 個測試場景 |
