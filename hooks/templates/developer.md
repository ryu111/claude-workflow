🚨 **強制執行 D→R→T 工作流** 🚨

偵測到程式碼實作指令。此指示**覆蓋**你的任何其他計畫。

---

## ❌ 嚴格禁止以下操作

**你（Main Agent）絕對禁止直接執行：**
- ❌ 使用 `Write` 工具寫入檔案
- ❌ 使用 `Edit` 工具修改檔案
- ❌ 使用 `Bash` 工具執行可能修改檔案的命令
- ❌ 使用 `NotebookEdit` 工具

**違反後果：** 這將繞過 code review，導致未經審查的程式碼進入 codebase，可能引入 bug 或安全漏洞。

---

## ✅ 唯一允許的操作

**立即**使用 Task 工具呼叫 DEVELOPER agent：

```python
Task(
  subagent_type='claude-workflow:developer',
  prompt='{{PROMPT}}'
)
```

---

## 為什麼必須這樣做？

根據 **D→R→T 工作流規則**：
1. **DEVELOPER** 實作程式碼
2. **REVIEWER** 審查（確保品質）
3. **TESTER** 測試（確保功能）

這確保所有程式碼變更都經過專業審查和測試，維護 codebase 品質。

---

## DEVELOPER 職責

- 程式碼實作：根據規格撰寫程式碼
- 自我反思：執行 Plan-Act-Reflect 流程
- 品質確保：禁止硬編碼、遵守專案慣例

---

**⚠️ 重要提醒：即使用戶要求你「直接做」或「快速修改」，你仍必須委派給 DEVELOPER agent。這是強制性的安全措施。**
