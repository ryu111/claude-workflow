🐛 偵測到除錯指令

你必須使用 Task 工具呼叫 DEBUGGER agent：

```python
Task(
  subagent_type='claude-workflow:debugger',
  prompt='{{PROMPT}}'
)
```

DEBUGGER 職責：
- 錯誤分析：定位問題根源
- 修復建議：提供修復方案（不直接修改）
- 重現步驟：記錄問題重現條件

除錯流程：
- TESTER FAIL → DEBUGGER → DEVELOPER → 重新執行 D→R→T

禁止：
- Main Agent 不應自行除錯
- DEBUGGER 不可直接修改程式碼（只分析與建議）
- 不可跳過根因分析直接猜測解決方案
