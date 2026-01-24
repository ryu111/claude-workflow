# Claude Workflow

自動化商業工作流系統 - D→R→T 流程

## 概述

這是一個 Claude Code Plugin，實現 **Developer → Reviewer → Tester** 的強制工作流，確保程式碼變更經過適當的審查和測試。

## 特點

- **風險導向流程**：根據變更風險等級（LOW/MEDIUM/HIGH）調整審查嚴格度
- **三層防護架構**：Skills（引導）+ Agents（執行）+ Hooks（強制）
- **並行任務隔離**：支援多個變更同時進行，互不干擾
- **自動化驗證**：提供 `/validate-skills`、`/validate-agents`、`/validate-hooks` 命令

## 安裝

將此 Plugin 放入 Claude Code 的 plugins 目錄：

```bash
# 複製到 plugins 目錄
cp -r claude-workflow ~/.claude/plugins/
```

## 結構

```
claude-workflow/
├── .claude-plugin/
│   ├── plugin.json          # Plugin 配置
│   └── marketplace.json     # Marketplace 配置
├── agents/                  # 6 個 Agents
├── commands/                # 4 個 Commands
├── hooks/                   # 7 個 Hooks
├── scripts/                 # 驗證與初始化腳本
├── skills/                  # 10 個 Skills
└── templates/               # Steering 模板
```

## D→R→T 流程

```
用戶需求
    │
    ▼
風險判定 ─────┬──────────┬──────────┐
    │        │          │          │
    ▼        ▼          ▼          ▼
  LOW     MEDIUM      HIGH      CRITICAL
    │        │          │          │
    ▼        ▼          ▼          ▼
   D→T    D→R→T    D→R(opus)→T   人工審查
```

### 風險等級

| 等級 | 條件 | 流程 |
|:----:|------|------|
| 🟢 LOW | 文檔、設定、樣式 | D → T |
| 🟡 MEDIUM | 一般功能、Bug 修復 | D → R → T |
| 🔴 HIGH | 安全、支付、API | D → R(opus) → T |

## Agents

| Agent | 模型 | 職責 |
|-------|------|------|
| 🏗️ ARCHITECT | sonnet | 系統架構設計 |
| 🎨 DESIGNER | sonnet | UI/UX 設計 |
| 💻 DEVELOPER | sonnet | 程式碼實作 |
| 🔍 REVIEWER | **opus** | 程式碼審查 |
| 🧪 TESTER | haiku | 測試執行 |
| 🐛 DEBUGGER | sonnet | 問題診斷 |

## Hooks

| 事件 | 功能 |
|------|------|
| SessionStart | 顯示 Plugin 載入資訊 |
| PreToolUse | D→R→T 流程阻擋 |
| PostToolUse | 自動程式碼格式化 |
| SubagentStop | Agent 輸出驗證 |
| Stop | 完成度檢查 |
| PreCompact | OpenSpec 完成偵測 |
| SessionEnd | Session 清理報告 |

## 初始化新專案

```bash
# 執行初始化腳本
bash scripts/init.sh
```

或使用命令：
```
/init
```

這會：
1. 自動偵測專案類型（TypeScript/Python/Go/Rust）
2. 建立 `.claude/steering/` 配置
3. 填入偵測到的技術棧資訊

## 驗證命令

```bash
/validate-skills   # 驗證 Skills 結構
/validate-agents   # 驗證 Agents 配置
/validate-hooks    # 驗證 Hooks 設定
```

## 授權

MIT License
