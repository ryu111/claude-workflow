# Agent 狀態顯示格式

每個 Agent 啟動和結束時，必須顯示明確狀態，以便追蹤工作流進度。

## Main Agent 動作格式

```markdown
## 🤖 MAIN 讀取 [檔案/目錄]
## 🤖 MAIN 分析任務依賴
## 🤖 MAIN 更新 tasks.md
## 🤖 MAIN 準備委派任務
## 🤖 MAIN 等候用戶指示
```

## Sub Agent 啟動時格式

```markdown
## 🏗️ ARCHITECT 開始規劃 [任務描述]
## 💻 DEVELOPER 開始實作 [Task X.X - 任務名稱]
## 🔍 REVIEWER 開始審查 [檔案/模組名稱]
## 🧪 TESTER 開始測試 [測試範圍]
## 🐛 DEBUGGER 開始除錯 [問題描述]
## 🎨 DESIGNER 開始設計 [UI/UX 範圍]
```

## 並行啟動格式

當同時啟動多個 Agent 時：

```markdown
## ⚡ 啟動 3 個 💻 DEVELOPER 並行處理：
- Task 1.1: 建立 UserService
- Task 1.2: 建立 AuthService
- Task 2.1: 建立 PaymentService
```

```markdown
## ⚡ 並行啟動：
- 💻 DEVELOPER: Task 1.1
- 🔍 REVIEWER: Task 2.1（已完成開發）
- 🧪 TESTER: Task 3.1（已通過審查）
```

## 結束時格式

### 成功完成

```markdown
## ✅ 💻 DEVELOPER 完成 Task 1.1。啟動 🔍 R → 🧪 T
## ✅ 🔍 REVIEWER 通過審查。啟動 🧪 TESTER
## ✅ 🧪 TESTER 通過 (15/15 tests)。Task 1.1 完成
```

### 發現問題

```markdown
## ❌ 🔍 REVIEWER 發現 2 個問題。返回 💻 DEVELOPER 修復
## ❌ 🧪 TESTER 失敗 (3/15 tests)。返回 💻 DEVELOPER 修復
```

### 需要協助

```markdown
## ⚠️ 💻 DEVELOPER 需要澄清：[問題描述]
## ⚠️ 🧪 TESTER 等待：測試環境未就緒
```

## Skills 使用提示

當 Agent 使用特定 skills 時，在啟動訊息中標註：

```markdown
## 💻 DEVELOPER 開始實作 Task 2.1 (使用 dev, ui-design skills)
## 🧪 TESTER 開始測試 (使用 test, debugging skills)
## 🎨 DESIGNER 開始設計 (使用 ui-design skills)
```

## Session Report 格式

工作結束時的總結報告：

```
═══ Session Report ═══
✅ D→R→T: X/X (100%)
⚡ 並行: Y/Y (100%)
📝 變更: Z files, ±N lines
═══════════════════════
```

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

## Agent 啟動時格式（增強版）

```markdown
# ═══════════════════════════════════════════════════════════
# ⚡ 啟動 💻 DEVELOPER 開始實作 [Task X.X - 任務名稱]
# ═══════════════════════════════════════════════════════════
```

## Agent 結束時格式（增強版）

```markdown
# ═══════════════════════════════════════════════════════════
# ✅ 💻 DEVELOPER 完成 Task 1.1。啟動 🔍 R → 🧪 T
# ═══════════════════════════════════════════════════════════
```

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
