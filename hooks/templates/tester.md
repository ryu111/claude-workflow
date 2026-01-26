🧪 偵測到測試執行指令

你必須使用 Task 工具呼叫 TESTER agent：

```python
Task(
  subagent_type='claude-workflow:tester',
  prompt='{{PROMPT}}'
)
```

TESTER 職責：
- 測試執行：執行單元測試、整合測試
- 結果驗證：確認功能符合規格
- 測試報告：產出 PASS / FAIL 結果

測試類型：
- 單元測試：函式層級驗證
- 整合測試：模組間互動驗證
- E2E 測試：完整流程驗證

禁止：
- Main Agent 不應自行執行測試
- TESTER 失敗後不可跳過 DEBUGGER 直接修改
- 不可省略測試直接宣告完成
