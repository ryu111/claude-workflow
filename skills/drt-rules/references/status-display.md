# Agent 狀態顯示格式

每個 Agent 啟動和結束時，**必須**使用增強版放大顯示格式，以便追蹤工作流進度。

## 統一格式規範

**所有 Agent 必須使用以下增強版格式（唯一標準）：**

### Main Agent 委派格式

```
## ⚡ 🤖 MAIN 委派 [AGENT_NAME] 執行 [任務描述]
```

### Main Agent 收到結果

```
## ✅ 🤖 MAIN 收到 [AGENT_NAME] 完成報告
```

### Main Agent 流程完成

```
## 🎉 D→R→T 流程完成！任務 [Task X.X] 已通過所有階段
```

---

## Subagent 啟動格式

### ARCHITECT
```
## ⚡ 🏗️ ARCHITECT 開始規劃 [任務描述]
```

### DESIGNER
```
## ⚡ 🎨 DESIGNER 開始設計 [UI/UX 範圍]
```

### DEVELOPER
```
## ⚡ 💻 DEVELOPER 開始實作 [Task X.X - 任務名稱]
```

### REVIEWER
```
## ⚡ 🔍 REVIEWER 開始審查 [檔案/模組名稱]
```

### TESTER
```
## ⚡ 🧪 TESTER 開始測試 [測試範圍]
```

### DEBUGGER
```
## ⚡ 🐛 DEBUGGER 開始分析 [問題描述]
```

---

## Subagent 結束格式

### ARCHITECT
```
## ✅ 🏗️ ARCHITECT 完成規劃。等待用戶審核
```

### DESIGNER
```
## ✅ 🎨 DESIGNER 完成設計。啟動 💻 DEVELOPER
```

### DEVELOPER
```
## ✅ 💻 DEVELOPER 完成實作。啟動 🔍 REVIEWER → 🧪 TESTER
```

### REVIEWER（通過）
```
## ✅ 🔍 REVIEWER 通過審查。啟動 🧪 TESTER
```

### REVIEWER（拒絕）
```
## ❌ 🔍 REVIEWER 發現 X 問題。返回 💻 DEVELOPER
```

### TESTER（通過）
```
## ✅ 🧪 TESTER 通過測試。任務完成！
```

### TESTER（失敗）
```
## ❌ 🧪 TESTER 測試失敗。啟動 🐛 DEBUGGER
```

### DEBUGGER
```
## ✅ 🐛 DEBUGGER 完成分析。返回 💻 DEVELOPER
```

---

## 並行啟動格式

當同時啟動多個 Agent 時：

```
## ⚡ 並行啟動 3 個 💻 DEVELOPER

- Task 1.1: 建立 UserService
- Task 1.2: 建立 AuthService
- Task 2.1: 建立 PaymentService
```

---

## Session Report 格式

工作結束時的總結報告：

```
## 📊 Session Report

✅ D→R→T: X/X (100%)
⚡ 並行: Y/Y (100%)
📝 變更: Z files, ±N lines
```

---

## 任務執行報告格式

每個任務結束時，Main Agent 必須輸出執行報告：

```markdown
## 📊 任務執行報告

| 階段 | Agent | 狀態 | 說明 |
|------|-------|------|------|
| 規劃 | 🏗️ ARCHITECT | ✅ | 設計系統架構 |
| 開發 | 💻 DEVELOPER | ✅ | 建立核心類別 |
| 審查 | 🔍 REVIEWER | ✅ | 發現 3 個問題 |
| 修復 | 💻 DEVELOPER | ❌ Main 自己做 | ⚠️ 違反 D→R→T |
| 測試 | 🧪 TESTER | ❌ 未執行 | ⚠️ 缺少測試 |

**D→R→T 合規率**: 3/5 (60%) ⚠️
```

### 狀態標記

| 標記 | 意義 |
|------|------|
| ✅ | 正確使用 Sub Agent |
| ❌ Main 自己做 | 違反委派原則 |
| ❌ 未執行 | 跳過該階段 |
| ⏭️ 略過 | 該任務不需要此階段 |

## Emoji 速查表

| Emoji | Agent | 用途 |
|-------|-------|------|
| 🤖 | MAIN | Main Agent 動作 |
| 🏗️ | ARCHITECT | 規劃、架構設計 |
| 💻 | DEVELOPER | 程式碼實作 |
| 🔍 | REVIEWER | 程式碼審查 |
| 🧪 | TESTER | 測試驗證 |
| 🐛 | DEBUGGER | 除錯排查 |
| 🎨 | DESIGNER | UI/UX 設計 |
| ⚡ | - | 並行操作 |
| ✅ | - | 成功完成 |
| ❌ | - | 失敗/問題 |
| ⚠️ | - | 警告/需協助 |
