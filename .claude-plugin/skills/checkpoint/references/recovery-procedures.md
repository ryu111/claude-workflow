# 狀態恢復程序

## 恢復前檢查清單

### 1. Checkpoint 有效性

```bash
# 檢查 checkpoint 檔案是否存在
test -f .claude/checkpoint.yaml && echo "✅ Checkpoint exists" || echo "❌ No checkpoint"

# 驗證 YAML 格式
yq eval '.' .claude/checkpoint.yaml > /dev/null 2>&1 && echo "✅ Valid YAML" || echo "❌ Invalid YAML"
```

### 2. Git 狀態一致性

```bash
# 檢查是否有未提交的變更
git status --porcelain

# 檢查分支是否正確
git branch --show-current

# 檢查是否與遠端同步
git fetch origin && git status -uno
```

### 3. 檔案完整性

檢查 checkpoint 中記錄的已修改檔案是否仍存在：

```bash
# 列出 checkpoint 中的檔案
yq eval '.progress.completed[].files_modified[]' .claude/checkpoint.yaml | while read file; do
  test -f "$file" && echo "✅ $file" || echo "❌ $file (missing)"
done
```

---

## 恢復流程

### 情況 1: 正常恢復（無衝突）

```
1. 讀取 checkpoint.yaml
2. 驗證當前環境與 checkpoint 一致
3. 從 current_step 繼續執行
4. 更新 checkpoint 狀態
```

### 情況 2: 檔案被外部修改

**偵測方式**:
```bash
# 比較檔案 hash
sha256sum file.ts > .claude/hashes/file.ts.sha256
diff .claude/hashes/file.ts.sha256 .claude/hashes/file.ts.sha256.checkpoint
```

**處理選項**:

| 選項 | 動作 | 適用情況 |
|------|------|----------|
| A | 使用當前版本，更新 checkpoint | 外部修改是正確的 |
| B | 恢復到 checkpoint 版本 | 外部修改是錯誤的 |
| C | 手動合併 | 兩者都有價值 |

### 情況 3: 分支已變更

**偵測方式**:
```bash
# 檢查分支是否存在
git rev-parse --verify checkpoint_branch 2>/dev/null
```

**處理選項**:

| 選項 | 動作 | 適用情況 |
|------|------|----------|
| A | 切換到 checkpoint 分支 | 分支仍存在 |
| B | 重建分支 | 分支被刪除但 commits 存在 |
| C | 從頭開始 | 分支和 commits 都不存在 |

### 情況 4: 依賴已更新

**偵測方式**:
```bash
# 比較 lock 檔案
diff package-lock.json .claude/snapshots/package-lock.json
```

**處理選項**:

| 選項 | 動作 | 適用情況 |
|------|------|----------|
| A | 使用新依賴，重新測試 | 小版本更新 |
| B | 恢復原依賴 | 大版本更新可能不相容 |

---

## 錯誤恢復

### 可重試錯誤恢復

```yaml
# checkpoint.yaml 中的錯誤記錄
errors:
  recoverable:
    - step: "2.1"
      error_type: "retryable"
      code: "ETIMEDOUT"
      retry_count: 1
```

**恢復動作**:
1. 等待指數退避時間 (2^retry_count 秒)
2. 重新嘗試該步驟
3. retry_count < 3 → 繼續重試
4. retry_count >= 3 → 升級為可修復錯誤

### 可修復錯誤恢復

```yaml
errors:
  recoverable:
    - step: "2.1"
      error_type: "recoverable"
      code: "ENOENT"
      message: "File not found: config.json"
```

**自動修復嘗試**:
1. 分析錯誤類型
2. 執行對應的修復腳本
3. 驗證修復結果
4. 成功 → 繼續，失敗 → 請求用戶介入

---

## 用戶介入提示

當自動恢復失敗時，顯示：

```markdown
## 🔄 需要您的協助

**任務**: [任務名稱]
**暫停於**: Step [X.X] - [步驟名稱]
**原因**: [錯誤描述]

### 問題詳情
[詳細的錯誤資訊]

### 建議的解決方案
1. [方案 A]
2. [方案 B]
3. [方案 C]

請選擇一個方案，或提供其他指示。
```
