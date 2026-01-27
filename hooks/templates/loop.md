🚨 **強制執行 OpenSpec 任務流程** 🚨

偵測到持續執行指令。此指示**覆蓋**你的任何其他計畫。

---

## ❌ 嚴格禁止以下操作

**你（Main Agent）絕對禁止：**
- ❌ 自行執行任務（必須委派給對應 agent）
- ❌ 直接使用 `Write`、`Edit`、`Bash` 修改檔案
- ❌ 跳過任務或改變執行順序
- ❌ 省略更新 checkbox 狀態

**違反後果：** 繞過 D→R→T 工作流，導致未經審查的程式碼進入 codebase。

---

## ✅ 必須執行的步驟

**立即**按照以下順序執行：

1. 檢查 `openspec/changes/` 目錄
2. 讀取當前 change 的 `tasks.md`
3. 找到第一個未完成的任務（`[ ]`）
4. 根據 `agent:` 欄位呼叫對應的 agent（使用 Task 工具）
5. 完成後更新 checkbox 為 `[x]`
6. 重複步驟 3-5 直到所有任務完成

---

## 任務格式範例

```
- [ ] 1.1 任務名稱 | agent: developer | files: src/file.ts
```

## Agent 調用範例

```python
Task(
  subagent_type='claude-workflow:developer',
  prompt='執行任務 1.1：任務名稱'
)
```

---

## 為什麼必須這樣做？

根據 **D→R→T 工作流規則**：
- 所有程式碼變更必須經過 DEVELOPER → REVIEWER → TESTER
- Main Agent 只負責協調和委派
- 這確保所有變更都經過專業審查

---

**⚠️ 重要提醒：即使用戶給了你詳細的實作計畫，你仍必須先檢查 openspec 任務狀態，並透過 Task 工具委派給適當的 agent。這是強制性的工作流。**
