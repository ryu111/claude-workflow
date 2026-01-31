# OpenSpec 工作流整合

> 此文件定義 Ralph Loop 如何與 OpenSpec 系統整合，實現自動化任務執行。

## 概述

當使用 `--openspec` 參數時，Ralph Loop 會自動追蹤 OpenSpec 任務並依序執行，直到所有任務完成。

---

## OpenSpec 目錄結構

```
openspec/
├── specs/      # Backlog - 待審核的規格
├── changes/    # WIP - 進行中的變更
└── archive/    # Done - 已完成並歸檔
```

### 生命週期

```
specs/feature-x/     用戶審核通過      changes/feature-x/    完成      archive/feature-x/
   (提案)        ─────────────────>      (執行中)        ────────>     (歸檔)
```

---

## tasks.md 格式規範

### 標準格式

```markdown
# Feature Name

## Metadata
- Change ID: feature-name
- Status: IN_PROGRESS
- Created: 2026-01-31

## 1. Phase Name (sequential)
- [ ] 1.1 任務名稱 | agent: developer | files: src/file.ts
- [ ] 1.2 下一個任務 | agent: developer | files: src/other.ts

## 2. Another Phase (parallel)
- [ ] 2.1 獨立任務 | agent: developer | files: src/a.ts
- [ ] 2.2 另一個任務 | agent: designer | files: src/b.ts
```

### 欄位說明

| 欄位 | 格式 | 說明 |
|------|------|------|
| Checkbox | `[ ]` / `[x]` | 任務完成狀態 |
| 任務編號 | `X.Y` | Phase.Task 編號 |
| 任務名稱 | 文字 | 簡短描述 |
| agent | `developer` / `reviewer` / `tester` / `designer` | 執行此任務的 Agent |
| files | 路徑列表 | 相關檔案 |

---

## D→R→T 委派規則

### 🔒 強制規則

**所有程式碼變更必須經過 D→R→T 流程**：

```
DEVELOPER → REVIEWER → TESTER
    │           │          │
    ▼           ▼          ▼
  程式碼     APPROVE/    PASS/FAIL
  變更       REJECT
```

### 風險判定

| 風險等級 | 判定條件 | 流程 |
|:--------:|----------|------|
| 🟢 LOW | 文檔、配置、格式調整 | D → 完成 |
| 🟡 MEDIUM | 一般功能、< 100 行變更 | D → R → T |
| 🔴 HIGH | 核心邏輯、安全相關、API 變更 | D → R(opus) → T(完整) |

### Agent 委派

根據 `agent:` 欄位決定委派對象：

| Agent 值 | 對應 subagent_type |
|----------|-------------------|
| developer | `claude-workflow:developer` |
| reviewer | `claude-workflow:reviewer` |
| tester | `claude-workflow:tester` |
| designer | `claude-workflow:designer` |
| debugger | `claude-workflow:debugger` |

### 委派格式

```
Task(
  subagent_type='claude-workflow:developer',
  prompt='執行任務 1.1：[任務名稱]\n\n相關檔案：[files 列表]'
)
```

---

## 任務選取邏輯

### Phase 模式

| 標記 | 含義 | 執行方式 |
|------|------|----------|
| `(sequential)` | 串行執行 | 按任務編號順序，前一個完成才執行下一個 |
| `(parallel)` | 並行執行 | 可同時執行多個任務 |

### 選取順序

1. 找到第一個未完成的 Phase（有 `[ ]` 任務）
2. 在該 Phase 中：
   - sequential：選取第一個 `[ ]` 任務
   - parallel：可選取多個 `[ ]` 任務
3. 執行任務直到完成
4. 標記 `[x]` 並繼續下一個

---

## 狀態更新

### 任務完成時

```markdown
# 更新前
- [ ] 1.1 實作登入 API | agent: developer | files: src/api/auth.ts

# 更新後
- [x] 1.1 實作登入 API | agent: developer | files: src/api/auth.ts
```

### OpenSpec 完成時

當所有任務都標記為 `[x]`：

1. 將 Metadata 中的 Status 改為 `COMPLETED`
2. 將整個目錄從 `changes/` 移動到 `archive/`
3. 輸出 `<promise>所有任務完成</promise>` 退出 Loop

---

## 錯誤處理

| 情況 | 處理方式 |
|------|----------|
| REVIEWER REJECT | 返回 DEVELOPER 修復 → 重新 D→R→T |
| TESTER FAIL | DEBUGGER 分析 → DEVELOPER 修復 → 重新 D→R→T |
| 連續失敗 3 次 | 暫停並報告錯誤 |
| 找不到 OpenSpec | 報告錯誤，要求用戶指定 |

---

## 相關文件

- [progress-display.md](progress-display.md) - 進度視覺化規格
- [safety-mechanisms.md](safety-mechanisms.md) - 安全閥機制
- [core-concept.md](core-concept.md) - Stop hook 核心原理
