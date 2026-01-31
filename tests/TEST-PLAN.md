# Claude Workflow Plugin 測試計劃

> 版本: 1.0.0
> 建立日期: 2026-01-25
> 狀態: 進行中

---

## 目標

完整驗證 Claude Workflow Plugin 的所有組件：
- 9 個 Hooks（事件驅動的流程控制）
- 6 個 Agents（專業角色）
- 11 個 Skills（共用知識）
- 7 個 Commands（使用者指令）

---

## 組件清單

### Hooks（hooks.json）

| 事件 | 腳本 | 用途 |
|------|------|------|
| SessionStart | plugin-status-display.sh | 顯示 Plugin 載入資訊 |
| PreToolUse(Task) | workflow-gate.sh | D→R→T 流程阻擋 |
| SubagentStart | agent-status-display.sh | 顯示 Agent 啟動資訊 |
| SubagentStop | subagent-validator.sh | 驗證 Agent 輸出 |
| PostToolUse(Task) | subagent-validator.sh | 驗證 Agent 輸出 |
| PostToolUse(Write\|Edit) | auto-format.sh | 自動格式化 |
| Stop | drt-completion-checker.sh | 檢查 D→R→T 完成狀態 |
| PreCompact | openspec-complete-detector.sh | 偵測 OpenSpec 完成 |
| SessionEnd | session-cleanup-report.sh | 生成 Session 報告 |

### Agents（agents/）

| Agent | 職責 | 工具權限 |
|-------|------|----------|
| ARCHITECT | 系統設計 | Read, Glob, Grep, Write, Task |
| DESIGNER | UI/UX 設計 | Read, Glob, Grep, Write, Task |
| DEVELOPER | 程式碼實作 | Read, Glob, Grep, Write, Edit, Bash, Task |
| REVIEWER | 程式碼審查（唯讀） | Read, Glob, Grep |
| TESTER | 執行測試 | Read, Glob, Grep, Bash |
| DEBUGGER | 除錯分析 | Read, Glob, Grep, Write, Task |

### Skills（skills/）

| Skill | 觸發詞 | 用途 |
|-------|--------|------|
| drt-rules | D→R→T, workflow | 核心流程規則 |
| openspec | OpenSpec, spec, tasks.md | 規格文件格式 |
| development | develop, implement, coding | 開發知識 |
| code-review | review, APPROVE, REJECT | 審查知識 |
| test | test, PASS, FAIL, coverage | 測試知識 |
| debugging | debug, error, 5 Whys | 除錯知識 |
| ui-design | design, UI, UX, CSS | 設計知識 |
| error-handling | error, exception, fallback | 錯誤處理 |
| checkpoint | checkpoint, state, save | 狀態保存 |
| orchestration | delegate, parallel, dispatch | 任務調度 |
| browser-automation | browser, E2E, UI 測試, claude-in-chrome, agent-browser | 瀏覽器自動化工具 |

### Commands（commands/）

| 指令 | 用途 |
|------|------|
| /plan | 啟動 ARCHITECT 規劃新功能 |
| /resume | 恢復執行現有的 OpenSpec |
| /loop | 持續執行直到所有任務完成 |
| /init | 初始化專案配置 |
| /validate-agents | 驗證 Agent 定義 |
| /validate-skills | 驗證 Skill 定義 |
| /validate-hooks | 驗證 Hook 配置 |

---

## 測試案例

### A. 基礎流程測試

#### TS-001: Session 啟動

**目標**: 驗證 SessionStart hook 正確觸發

**驗證點**:
- [x] plugin-status-display.sh 被呼叫
- [x] 顯示 Plugin 資訊和 D→R→T 說明
- [x] 不產生錯誤或例外

**測試方法**: 啟動新 Session，觀察輸出

---

#### TS-002: 標準 D→R→T 流程

**目標**: 驗證完整 DEVELOPER → REVIEWER → TESTER 流程

**步驟**:
1. 啟動 DEVELOPER 實作功能
2. DEVELOPER 完成後，啟動 REVIEWER
3. REVIEWER APPROVE
4. 啟動 TESTER
5. TESTER PASS

**驗證點**:
- [ ] 每個 Agent 啟動時顯示正確的提示框
- [ ] SubagentStop/PostToolUse 正確記錄狀態
- [ ] 狀態檔案正確更新
- [ ] 流程順利完成

**狀態檔案**: `.claude/.drt-workflow-state`

---

#### TS-003: 違規阻擋（跳過 REVIEWER）

**目標**: 驗證 PreToolUse hook 正確阻擋違規操作

**步驟**:
1. 啟動 DEVELOPER 實作功能
2. DEVELOPER 完成
3. 嘗試直接啟動 TESTER（跳過 REVIEWER）

**預期結果**:
- workflow-gate.sh 輸出 `{"decision":"block","reason":"..."}`
- 顯示錯誤訊息：「不允許跳過 REVIEWER 直接進行測試」

**測試腳本**: `tests/scripts/test-ts-003.sh`

---

### B. 反向流程測試

#### TS-004: REVIEWER REJECT

**目標**: 驗證 REJECT 後正確返回 DEVELOPER

**步驟**:
1. DEVELOPER 完成實作
2. REVIEWER 審查，發出 REJECT
3. 系統提示返回 DEVELOPER

**驗證點**:
- [ ] subagent-validator.sh 偵測到 REJECT 關鍵字
- [ ] 狀態檔記錄 `{"agent":"reviewer","result":"reject",...}`
- [ ] 顯示「下一步: 請委派 DEVELOPER 修復」

---

#### TS-005: TESTER FAIL

**目標**: 驗證 FAIL 後進入 DEBUGGER 流程

**步驟**:
1. 完成 D→R→T 流程到 TESTER
2. TESTER 執行測試，發出 FAIL
3. 系統提示啟動 DEBUGGER

**驗證點**:
- [ ] subagent-validator.sh 偵測到 FAIL 關鍵字
- [ ] 狀態檔記錄 `{"agent":"tester","result":"fail",...}`
- [ ] 顯示「下一步: 請委派 DEBUGGER 分析」

---

### C. 風險等級測試

#### TS-006: LOW 風險快速通道

**目標**: 驗證 LOW 風險可跳過 REVIEWER

**步驟**:
1. DEVELOPER 修改文檔/配置（LOW 風險）
2. 直接啟動 TESTER（跳過 REVIEWER）
3. TESTER PASS

**驗證點**:
- [ ] workflow-gate.sh 允許 D→T 流程
- [ ] 不顯示違規阻擋

**備註**: 目前 workflow-gate.sh 未實作風險等級判定，此測試預期失敗

---

#### TS-007: HIGH 風險深度審查

**目標**: 驗證 HIGH 風險使用 opus 模型

**步驟**:
1. DEVELOPER 修改 /auth/ 或 /api/ 路徑檔案
2. 系統判定為 HIGH 風險
3. REVIEWER 使用 opus 模型

**驗證點**:
- [ ] 風險等級判定邏輯正確
- [ ] REVIEWER Task 使用 model: opus

**備註**: 需要檢查 reviewer.md 中的 model 設定

---

### D. 進階場景測試

#### TS-008: 並行任務隔離

**目標**: 驗證多個 Change ID 狀態獨立

**步驟**:
1. 啟動 Change-A 的 DEVELOPER（prompt 包含 [change-a]）
2. 啟動 Change-B 的 DEVELOPER（prompt 包含 [change-b]）
3. Change-A 進入 REVIEWER
4. Change-B 仍在 DEVELOPER

**驗證點**:
- [ ] 存在 `.claude/.drt-state-change-a`
- [ ] 存在 `.claude/.drt-state-change-b`
- [ ] 兩個狀態檔案獨立更新

**測試腳本**: `tests/scripts/test-ts-008.sh`

---

#### TS-009: OpenSpec 生命週期

**目標**: 驗證 OpenSpec 從 specs → changes → archive

**步驟**:
1. 在 `openspec/specs/` 建立新規格
2. 審核通過後移動到 `openspec/changes/`
3. 完成後移動到 `openspec/archive/`

**驗證點**:
- [ ] 目錄結構正確
- [ ] PreCompact hook 偵測完成
- [ ] 建議歸檔

---

#### TS-010: /loop 持續執行

**目標**: 驗證 /loop 自動完成所有任務

**步驟**:
1. 建立 OpenSpec 包含多個任務
2. 執行 /loop
3. 觀察自動執行直到所有任務完成

**驗證點**:
- [ ] loop.md 指令正確載入
- [ ] 任務依序執行
- [ ] 遇到阻礙時正確停止

---

#### TS-011: Session 結束報告

**目標**: 驗證 SessionEnd hook 產生報告

**驗證點**:
- [ ] session-cleanup-report.sh 被呼叫
- [ ] 報告包含統計資訊

**備註**: 需要在 Session 結束時觸發，難以自動化測試

---

#### TS-012: 狀態過期處理

**目標**: 驗證 30 分鐘過期機制

**步驟**:
1. 建立狀態檔案，timestamp 為 31 分鐘前
2. 嘗試執行流程

**驗證點**:
- [ ] workflow-gate.sh 判定 STATE_VALID=false
- [ ] 顯示「無法驗證流程狀態（可能已過期）」

**測試腳本**: `tests/scripts/test-ts-012.sh`

---

### E. 組件驗證測試

#### TS-013: browser-automation Skill 驗證

**目標**: 驗證 browser-automation skill 結構和引用正確

**驗證點**:
- [ ] `skills/browser-automation/SKILL.md` 存在
- [ ] YAML frontmatter 包含必要欄位（name, description, user-invocable, disable-model-invocation）
- [ ] `references/testing-patterns.md` 存在
- [ ] 至少有 1 個 Agent 引用此 skill（tester, designer, debugger）
- [ ] 工具對照表完整（claude-in-chrome vs agent-browser）

**測試腳本**: `tests/scripts/test-ts-013.sh`

---

#### TS-014: Agent Skills 引用一致性

**目標**: 驗證所有 Agent 引用的 skills 都存在

**驗證點**:
- [ ] 每個 Agent frontmatter 中的 skills 都有對應目錄
- [ ] 被引用的 skill 有有效的 SKILL.md
- [ ] 無孤立 skill（未被任何 Agent 引用）

**測試腳本**: `tests/scripts/test-ts-014.sh`

---

## 測試結果追蹤

| ID | 名稱 | 狀態 | 備註 |
|:--:|------|:----:|------|
| TS-001 | Session 啟動 | ⏳ | |
| TS-002 | 標準 D→R→T 流程 | ⏳ | |
| TS-003 | 違規阻擋 | ⏳ | |
| TS-004 | REVIEWER REJECT | ⏳ | |
| TS-005 | TESTER FAIL | ⏳ | |
| TS-006 | LOW 風險快速通道 | ⏳ | 未實作 |
| TS-007 | HIGH 風險深度審查 | ⏳ | 需檢查 |
| TS-008 | 並行任務隔離 | ⏳ | |
| TS-009 | OpenSpec 生命週期 | ⏳ | |
| TS-010 | /loop 持續執行 | ⏳ | |
| TS-011 | Session 結束報告 | ⏳ | |
| TS-012 | 狀態過期處理 | ⏳ | |
| TS-013 | browser-automation Skill | ⏳ | |
| TS-014 | Agent Skills 引用一致性 | ⏳ | |

**圖例**: ✅ PASS | ❌ FAIL | ⏳ 待測試 | 🔧 已知問題

---

## 執行指引

### 手動測試

```bash
# 清除狀態
rm -f .claude/.drt-*

# 執行單一測試
bash tests/scripts/test-ts-XXX.sh

# 執行所有測試
bash tests/scripts/run-all-tests.sh
```

### 自動化測試

```bash
# 啟用 Bypass 模式（繞過 D→R→T 檢查）
export CLAUDE_WORKFLOW_BYPASS=true

# 或建立配置文件
touch .claude/.drt-bypass

# 執行測試後記得移除
rm -f .claude/.drt-bypass
```

### 查看除錯日誌

```bash
# Hook 除錯日誌
tail -f /tmp/claude-workflow-debug.log

# 狀態檔案
cat .claude/.drt-workflow-state | jq .
```

---

## 相關文件

- [DRT-FLOW-TEST.md](./DRT-FLOW-TEST.md) - 舊版測試計劃
- [CLAUDE.md](../CLAUDE.md) - 專案指引
- [hooks.json](../hooks/hooks.json) - Hook 配置
