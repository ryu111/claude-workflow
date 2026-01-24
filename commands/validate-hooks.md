---
name: validate-hooks
description: 驗證 plugin 中所有 hooks 的配置和腳本
user-invocable: true
disable-model-invocation: true
---

# 驗證 Hooks 配置

請執行以下驗證腳本，檢查所有 hooks 配置：

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-hooks.sh
```

## 驗證項目

1. **hooks.json 存在性** - 確認配置檔案存在
2. **JSON 語法** - 驗證 JSON 格式正確
3. **事件類型** - 檢查是否為支援的 Hook 事件
4. **腳本存在性** - 確認所有引用的腳本檔案存在
5. **執行權限** - 確認腳本有執行權限
6. **路徑變數** - 檢查是否使用 `${CLAUDE_PLUGIN_ROOT}`

## 支援的 Hook 事件

| 事件 | 觸發時機 |
|------|----------|
| SessionStart | Session 開始時 |
| PreToolUse | 工具執行前 |
| PostToolUse | 工具執行後 |
| SubagentStop | Agent 完成時 |
| Stop | Session 停止前 |
| PreCompact | Context 壓縮前 |
| SessionEnd | Session 結束時 |
| Notification | 通知發送時 |
| UserPromptSubmit | 用戶提交 Prompt 時 |

## 預期輸出

驗證成功：
```
✅ 所有 Hooks 驗證通過
```

驗證失敗：
```
❌ 驗證失敗，請修復上述錯誤
```

執行驗證後，根據結果修復任何問題。
