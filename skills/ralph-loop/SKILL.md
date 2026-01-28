---
name: ralph-loop
description: |
  Ralph Loop 持續執行模式的使用指引。
  這是官方 ralph-loop 的使用指引 skill，提供正確使用方式避免錯誤。
  觸發詞：ralph, loop, 持續, 繼續, 做完, 全部執行, 自動化, continuous, auto, run all
user-invocable: false
disable-model-invocation: false
---

# Ralph Loop 使用指引

> 這是官方 ralph-loop 的使用指引，不是另一個 Loop 實作。

## 快速開始

```bash
# 啟動 Ralph Loop
/ralph-loop "完成所有待辦任務" --max-iterations 10

# 取消
/cancel-ralph
```

## ⚠️ 必須設定 --max-iterations

**避免無限迴圈**：永遠設定 `--max-iterations`（建議 5-20）。

## 核心機制

Ralph Loop 使用 Stop hook 攔截 Claude 退出，將任務反饋回去持續執行。

**退出條件**：
1. 達到 `--max-iterations`
2. 輸出 `<promise>TEXT</promise>` 標籤
3. 執行 `/cancel-ralph`

## 與 D→R→T 整合

在 Loop 中仍需遵循 D→R→T 流程：
- 委派 DEVELOPER 實作
- 委派 REVIEWER 審查
- 委派 TESTER 測試

## 目錄結構

```
skills/ralph-loop/
├── SKILL.md          # 本文件（使用指引）
├── references/       # 詳細參考文件
├── commands/
│   ├── ralph-loop.md # 啟動命令
│   ├── cancel-ralph.md # 取消命令
│   └── help.md       # 幫助
├── hooks/
│   ├── hooks.json    # Hook 配置
│   └── stop-hook.sh  # 核心邏輯
└── scripts/
    └── setup-ralph-loop.sh # 初始化
```

---

## 資源

### References
- [core-concept.md](references/core-concept.md) - Stop hook 運作原理、自我參照迴圈
- [prompt-best-practices.md](references/prompt-best-practices.md) - 撰寫有效 Prompt 的技巧
- [use-cases.md](references/use-cases.md) - 適用/不適用場景、實際案例

### Commands
- [ralph-loop.md](commands/ralph-loop.md) - 啟動 Ralph Loop
- [cancel-ralph.md](commands/cancel-ralph.md) - 取消 Loop
- [help.md](commands/help.md) - 幫助資訊

### External Resources
- [官方 GitHub](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-loop)
- [Ralph 技術原文](https://ghuntley.com/ralph/)
