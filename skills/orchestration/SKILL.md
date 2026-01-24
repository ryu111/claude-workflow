---
name: orchestration
description: |
  Agent 調度與任務分配規則。自動載入於任務規劃、委派、並行執行決策時。
  觸發詞：委派, delegate, 分配, assign, 並行, parallel, 串行, sequential, 調度, dispatch, 啟動 Agent, 觸發
user-invocable: false
disable-model-invocation: false
---

# 任務調度規則

## 核心原則

Main Agent 是**監督者**，不是**執行者**。

## 委派矩陣

### 必須委派

| 任務類型 | 委派給 | 說明 |
|----------|--------|------|
| 寫程式碼 | DEVELOPER | 任何 code 變更 |
| 審查程式碼 | REVIEWER | 必須由非作者審查 |
| 執行測試 | TESTER | 驗證功能正確性 |
| 除錯分析 | DEBUGGER | 測試失敗後分析 |
| 系統設計 | ARCHITECT | 新功能規劃 |
| UI/UX 設計 | DESIGNER | 介面相關設計 |

### 可直接處理

Main 可直接處理以下內容（但仍需 R → T）：

- 文檔檔案：`*.md`
- 配置檔案：`*.json`, `*.yaml`, `*.toml`
- 環境變數：`.env`, `.env.*`
- OpenSpec 規格文件

## 並行執行

### 判斷標準

| 條件 | 執行方式 |
|------|----------|
| 任務間無依賴 | ✅ 並行 |
| 不同檔案、不同模組 | ✅ 並行 |
| Task B 需要 Task A 的輸出 | ❌ 串行 |
| 多個任務修改同一檔案 | ❌ 串行 |

### 並行啟動格式

```markdown
## ⚡ 並行啟動 3 個 DEVELOPER
- Task 2.1: 建立 UserService
- Task 2.2: 建立 AuthService
- Task 2.3: 建立 PaymentService
```

### 並行錯誤處理

| 情況 | 處理方式 |
|------|----------|
| 其中一個 REJECT | 只重試該任務，其他繼續 |
| 其中一個 FAIL | 只 DEBUG 該任務，其他繼續 |
| 多個失敗 | 依序處理，避免複雜度爆炸 |

## 觸發詞識別

| 用戶輸入關鍵字 | 觸發 Agent | 啟動流程 |
|----------------|------------|----------|
| 規劃, plan, 架構 | ARCHITECT | 建立 OpenSpec |
| 設計, design, UI | DESIGNER | Design → D → R → T |
| 實作, implement, 開發, 寫 | DEVELOPER | D → R → T |
| 審查, review, 檢查 | REVIEWER | R → T |
| 測試, test, 驗證 | TESTER | T |
| debug, 除錯, 修復 bug | DEBUGGER | Debug → D → R → T |
| 接手, resume | - | 恢復 OpenSpec |
| loop, 持續 | - | 持續執行模式 |

## 狀態顯示格式

### 啟動
```markdown
## 🏗️ ARCHITECT 開始規劃 [任務描述]
## 💻 DEVELOPER 開始實作 [Task X.X - 任務名稱]
## 🔍 REVIEWER 開始審查 [檔案/模組名稱]
## 🧪 TESTER 開始測試 [測試範圍]
## 🐛 DEBUGGER 開始分析 [失敗原因]
```

### 完成
```markdown
## ✅ DEVELOPER 完成 Task X.X → 啟動 REVIEWER
## ✅ REVIEWER APPROVE → 啟動 TESTER
## ✅ TESTER PASS (15/15 tests) → 任務完成
```

### 失敗
```markdown
## ❌ REVIEWER REJECT (2 issues) → 返回 DEVELOPER
## ❌ TESTER FAIL (3/15 tests) → 啟動 DEBUGGER
```

## 資源

### References

- [agent-capabilities.md](references/agent-capabilities.md) - 各 Agent 能力說明與選擇指南

### Templates

- [dispatch-decision.md](templates/dispatch-decision.md) - 調度決策範本

### Examples

- [parallel-execution.md](examples/parallel-execution.md) - 並行執行完整範例
