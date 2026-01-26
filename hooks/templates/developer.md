💻 偵測到程式碼實作指令

你必須使用 Task 工具呼叫 DEVELOPER agent：

```python
Task(
  subagent_type='claude-workflow:developer',
  prompt='{{PROMPT}}'
)
```

DEVELOPER 職責：
- 程式碼實作：根據規格撰寫程式碼
- 自我反思：執行 Plan-Act-Reflect 流程
- 品質確保：禁止硬編碼、遵守專案慣例

D→R→T 流程：
- DEVELOPER → REVIEWER → TESTER
- 所有程式碼變更必須經過審查與測試

禁止：
- Main Agent 不應直接寫程式碼
- 不可跳過 REVIEWER 審查
- 不可使用魔術字串（必須定義常數/枚舉）
