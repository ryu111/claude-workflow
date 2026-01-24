---
name: checkpoint
description: |
  狀態保存與恢復知識。自動載入於需要保存進度、恢復狀態、長時間任務相關情境。
  觸發詞：checkpoint, 檢查點, 狀態, state, 保存, save, 恢復, restore, resume, 進度, progress
user-invocable: false
disable-model-invocation: false
---

# 狀態檢查點知識

## 何時需要 Checkpoint

### 必要情境
- 任務執行時間 > 5 分鐘
- 涉及多個檔案的批次處理
- 需要外部服務回應的等待
- 用戶可能中斷的互動流程

### 狀態類型

| 類型 | 說明 | 範例 |
|------|------|------|
| 任務狀態 | 目前執行到哪個步驟 | `step: 3/5` |
| 資料狀態 | 已處理的資料 | `processed: [file1, file2]` |
| 決策狀態 | 已做的決定 | `decisions: { useCache: true }` |
| 錯誤狀態 | 遇到的問題 | `errors: [{ file: x, reason: y }]` |

## Checkpoint 格式

### 標準結構

```yaml
# .claude/checkpoint.yaml
version: 1
task_id: "task-uuid"
created_at: "2024-01-01T10:00:00Z"
updated_at: "2024-01-01T10:30:00Z"

status: "in_progress"  # pending | in_progress | paused | completed | failed

current_step:
  phase: "development"  # 目前階段
  index: 2              # 第幾步
  total: 5              # 總步數

progress:
  completed:
    - step: "parse_spec"
      result: "success"
      timestamp: "2024-01-01T10:05:00Z"
    - step: "create_files"
      result: "success"
      files_created: ["src/user.ts", "src/user.test.ts"]

  pending:
    - step: "implement_logic"
    - step: "run_tests"
    - step: "code_review"

context:
  spec_file: "specs/user-feature.md"
  working_branch: "feature/user"
  decisions:
    - question: "使用哪個 ORM?"
      answer: "Prisma"
      reason: "專案已有 Prisma 設定"

errors:
  recoverable:
    - step: "run_tests"
      error: "Connection timeout"
      retry_count: 1
  fatal: []
```

## 恢復策略

### 恢復流程

```
1. 讀取 checkpoint 檔案
2. 驗證狀態完整性
3. 確認環境一致性
4. 從最後成功步驟繼續
```

### 恢復前檢查

```markdown
## 恢復檢查清單
- [ ] checkpoint 檔案存在且有效
- [ ] 相關檔案未被外部修改
- [ ] Git 分支狀態一致
- [ ] 必要的環境變數存在
```

### 衝突處理

| 情況 | 處理方式 |
|------|----------|
| 檔案被修改 | 詢問用戶是否覆蓋 |
| 分支已變更 | 建議 rebase 或重新開始 |
| 依賴已更新 | 重新驗證相容性 |

## 自動保存時機

### 建議保存點
1. 每個主要步驟完成後
2. 做出重要決策後
3. 建立或修改檔案後
4. 執行外部命令後

### 保存頻率
- 快速任務（< 2 分鐘）：完成時保存
- 中等任務（2-10 分鐘）：每步驟保存
- 長時間任務（> 10 分鐘）：每 2-3 分鐘保存

## 報告格式

### 恢復提示

```markdown
## 🔄 發現未完成的任務

**任務**: [任務描述]
**進度**: 3/5 步驟完成
**暫停時間**: 2024-01-01 10:30

### 已完成
✅ 解析規格文件
✅ 建立檔案結構

### 待完成
⏸️ 實作邏輯（從這裡繼續）
⬚ 執行測試
⬚ 程式碼審查

是否要繼續這個任務？
```

## 資源

### Templates

- [checkpoint.yaml](templates/checkpoint.yaml) - Checkpoint 檔案範本

### References

- [recovery-procedures.md](references/recovery-procedures.md) - 狀態恢復程序詳細說明
