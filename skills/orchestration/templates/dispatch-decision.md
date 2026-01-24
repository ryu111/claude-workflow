# 調度決策範本

## 使用說明

Main Agent 在決定任務分派時，使用此範本記錄決策過程。

---

## 調度決策記錄

### 基本資訊

```markdown
**任務 ID**: [task-id]
**任務描述**: [簡述任務內容]
**來源**: [用戶請求 / OpenSpec / 上一階段輸出]
```

### 任務分析

```markdown
**任務類型**: [新功能 / Bug修復 / 重構 / 配置 / 文檔]
**影響範圍**: [單檔案 / 多檔案 / 跨模組]
**風險等級**: [🟢 LOW / 🟡 MEDIUM / 🔴 HIGH]
```

### 委派決策

```markdown
**委派給**: [ARCHITECT / DEVELOPER / DESIGNER / ...]
**原因**: [為什麼選擇這個 Agent]

**輸入資料**:
- [提供給 Agent 的資訊 1]
- [提供給 Agent 的資訊 2]

**預期輸出**:
- [期望 Agent 產出什麼]
```

### 執行方式

```markdown
**執行模式**: [串行 / 並行]
**依賴關係**: [無 / 依賴 Task X.X]
**預估複雜度**: [簡單 / 中等 / 複雜]
```

---

## 快速決策模板

### 單一任務委派

```markdown
## 🚀 委派 DEVELOPER

**任務**: Task 1.1 - 建立 UserService
**風險**: 🟡 MEDIUM
**輸入**:
- OpenSpec: openspec/changes/user-feature/tasks.md
- 檔案: src/services/user.ts
**後續**: DEVELOPER 完成 → REVIEWER → TESTER
```

### 並行任務委派

```markdown
## ⚡ 並行啟動 3 個 DEVELOPER

| Task | 描述 | 檔案 |
|------|------|------|
| 2.1 | 建立 UserService | src/services/user.ts |
| 2.2 | 建立 AuthService | src/services/auth.ts |
| 2.3 | 建立 PaymentService | src/services/payment.ts |

**並行原因**: 三個服務互不依賴，可同時開發
**匯合點**: Phase 3 開始前
```

### 流程切換

```markdown
## 🔄 流程轉換

**從**: DEVELOPER (Task 1.1 完成)
**到**: REVIEWER
**傳遞**:
- 修改的檔案: src/services/user.ts
- 變更摘要: 新增 createUser, getUser 方法
**審查重點**:
- 輸入驗證
- 錯誤處理
```

---

## 決策檢查清單

在做出調度決策前，確認：

- [ ] 任務類型是否正確識別？
- [ ] 風險等級是否合理？
- [ ] 委派的 Agent 是否正確？
- [ ] 是否提供足夠的輸入資訊？
- [ ] 執行模式（串行/並行）是否合理？
- [ ] 是否遵循 D→R→T 流程？
