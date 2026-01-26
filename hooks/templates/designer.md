🎨 偵測到 UI/UX 設計指令

你必須使用 Task 工具呼叫 DESIGNER agent：

```python
Task(
  subagent_type='claude-workflow:designer',
  prompt='{{PROMPT}}'
)
```

DESIGNER 職責：
- UI 設計：元件規格、視覺層次、響應式設計
- UX 流程：使用者旅程、互動設計
- 設計規範：Design Tokens、可及性標準

禁止：
- Main Agent 不應直接設計 UI
- 不可跳過設計階段直接開發
- 不可忽略可及性 (Accessibility) 考量
