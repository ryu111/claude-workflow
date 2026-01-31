---
description: "Start Ralph Loop in current session"
argument-hint: "PROMPT [--max-iterations N] [--completion-promise TEXT] [--openspec CHANGE_ID]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh:*)", "Read", "Glob", "Grep", "Write", "Edit", "Task"]
hide-from-slash-command-tool: "true"
---

# Ralph Loop Command

Execute the setup script to initialize the Ralph loop:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh" $ARGUMENTS
```

---

## 🔒 核心規則

**CRITICAL RULE**: If a completion promise is set, you may ONLY output it when the statement is completely and unequivocally TRUE. Do not output false promises to escape the loop, even if you think you're stuck or should exit for other reasons. The loop is designed to continue until genuine completion.

---

## 📋 OpenSpec 模式（--openspec）

當使用 `--openspec` 參數時，**必須**遵循以下執行邏輯：

### 🔄 強制持續執行

Loop 啟動後，你**必須**自主持續執行，直到所有任務完成。

| 原則 | 說明 |
|------|------|
| 🔄 持續執行 | 必須持續執行直到所有任務完成 |
| ⚡ 立即開始 | 每個任務完成後**立即**開始下一個任務 |
| 🚫 禁止詢問 | **不得**詢問用戶「是否繼續」 |
| ⏸️ 暫停條件 | **僅**在用戶明確說「暫停」或遇到無法解決的錯誤時中斷 |

### 📂 執行步驟

1. **讀取任務** → 從 `openspec/changes/{change-id}/tasks.md` 讀取任務列表
2. **找到未完成** → 找到第一個 `[ ]` 未完成任務
3. **委派執行** → 使用 Task 工具委派給對應 agent（根據 `agent:` 欄位）
4. **等待完成** → agent 完成 D→R→T 流程
5. **更新狀態** → 標記 `[x]` 完成
6. **顯示進度** → 顯示進度報告（見 [progress-display.md](../references/progress-display.md)）
7. **立即繼續** → **禁止詢問**，直接開始下一個任務
8. **重複** → 直到所有任務完成

### 🎯 D→R→T 委派規則

**所有程式碼變更必須經過 D→R→T 流程**：

| 風險等級 | 流程 |
|:--------:|------|
| 🟢 LOW | D → 完成 |
| 🟡 MEDIUM | D → R → T |
| 🔴 HIGH | D → R(opus) → T(完整) |

### 🚫 嚴格禁止

**你（Main Agent）絕對禁止：**
- ❌ 自行執行任務（必須委派給對應 agent）
- ❌ 直接使用 `Write`、`Edit`、`Bash` 修改程式碼檔案
- ❌ 跳過任務或改變執行順序
- ❌ 省略更新 checkbox 狀態
- ❌ 詢問用戶是否繼續

### ✅ 智能完成偵測

每完成一個任務後，**必須**檢查：

1. 讀取 `tasks.md` 檔案
2. 計算 checkbox 狀態（`- [x]` vs `- [ ]`）
3. 如果全部完成：
   - 顯示完成訊息
   - 輸出 `<promise>所有任務完成</promise>`
   - Loop 自動退出

---

## 📊 進度視覺化

每完成一個任務後，**必須**顯示：

```
╔════════════════════════════════════════════════════════════════╗
║                    🔁 Loop 模式運行中                           ║
╚════════════════════════════════════════════════════════════════╝

📊 總體進度: X/Y 任務完成 (Z%)
[████████████░░░░░░░░░░░░░░] Z%

🔄 當前: [任務編號] [任務名稱]
   └── D→R→T: DEVELOPER ✅ → REVIEWER 🔄 → TESTER ⏳

📈 迭代: #N / 100
```

---

## ⚠️ 安全閥機制

| 限制 | 數值 | 行為 |
|------|------|------|
| 最大迭代次數 | 100 | 暫停 Loop，等待用戶確認 |
| 連續錯誤次數 | 3 | 暫停 Loop，報告錯誤 |

---

## 📚 參考文件

- [openspec-workflow.md](../references/openspec-workflow.md) - OpenSpec 工作流詳細規則
- [progress-display.md](../references/progress-display.md) - 進度視覺化規格
- [safety-mechanisms.md](../references/safety-mechanisms.md) - 安全閥機制

---

## 通用模式

When you try to exit, the Ralph loop will feed the SAME PROMPT back to you for the next iteration. You'll see your previous work in files and git history, allowing you to iterate and improve.
