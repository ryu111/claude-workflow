🚨 **偵測到 Loop 關鍵字** 🚨

你需要啟動 Ralph Loop 來執行持續任務。

---

## 📋 執行步驟

### 1. 檢查 OpenSpec

首先檢查是否有進行中的 OpenSpec：

```bash
ls openspec/changes/ 2>/dev/null
```

### 2. 啟動 Ralph Loop

根據情況選擇：

**有 OpenSpec 時：**
```
/ralph-loop --openspec [change-id]
```

**無 OpenSpec 時（通用模式）：**
```
/ralph-loop "{{PROMPT}}" --max-iterations 50
```

---

## ⚠️ 重要提醒

- Ralph Loop 使用 Stop hook 強制持續執行
- 只有達到 `--max-iterations` 或輸出 `<promise>完成文字</promise>` 才會停止
- OpenSpec 模式會自動設定 completion_promise 為「所有任務完成」

---

## 📚 詳細規則

請參考：
- `skills/ralph-loop/references/openspec-workflow.md` - OpenSpec 工作流
- `skills/ralph-loop/references/progress-display.md` - 進度視覺化
- `skills/ralph-loop/references/safety-mechanisms.md` - 安全閥機制
