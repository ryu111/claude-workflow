🔍 偵測到程式碼審查指令

你必須使用 Task 工具呼叫 REVIEWER agent：

```python
Task(
  subagent_type='claude-workflow:reviewer',
  prompt='{{PROMPT}}'
)
```

REVIEWER 職責：
- 程式碼審查：品質、安全性、效能
- 風險評估：依照 D→R→T 規則評估變更風險等級
- 決策產出：APPROVE / APPROVE_WITH_MINOR / REJECT

REVIEWER 權限：
- 唯讀權限（Read, Glob, Grep）
- 不可修改程式碼

禁止：
- Main Agent 不應自行審查
- REVIEWER 不可直接修改程式碼
- 不可跳過安全性與效能檢查
