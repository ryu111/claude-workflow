🏗️ 偵測到系統規劃指令

你必須使用 Task 工具呼叫 ARCHITECT agent：

```python
Task(
  subagent_type='claude-workflow:architect',
  prompt='{{PROMPT}}'
)
```

ARCHITECT 職責：
- 需求分析：理解功能範圍與用戶需求
- 系統設計：模組劃分、依賴關係、技術選型
- 規格制定：建立 OpenSpec 文件於 openspec/specs/[change-id]/

禁止：
- Main Agent 不應直接回答規劃問題
- 不可跳過 ARCHITECT 自行設計
- 不可省略 OpenSpec 制定步驟
