# 流程強制策略：引導 vs 阻擋

## 概述

本文檔記錄 claude-workflow 插件的流程強制機制設計決策，以及與 oh-my-claudecode 的對比分析。

## 兩種強制方法

### 阻擋式（claude-workflow 採用）

透過 Hook 在 PreToolUse 時阻擋違規操作。

```
PreToolUse Hook
    │
    ▼
workflow-gate.sh / global-workflow-guard.sh
    │
    ├─ 違規 → 返回 ERROR，工具呼叫失敗
    │
    └─ 合規 → 允許執行
```

**優點**：
- 100% 強制，無法繞過
- 明確的錯誤回饋

**缺點**：
- 可能感覺「僵硬」
- 需要維護阻擋邏輯

### 引導式（oh-my-claudecode 採用）

透過 Skill 詳細說明 + Hook 注入提醒 + Agent Prompt 約束。

```
Layer 1: Skill 詳細引導
    │  詳細步驟，讓 Claude 知道「該怎麼做」
    ▼
Layer 2: Agent Prompt 約束
    │  強烈語言（MUST, NEVER），讓 Claude 知道「不能做什麼」
    ▼
Layer 3: Hook 動態注入
    │  偵測關鍵字後注入提醒訊息
    ▼
Claude 被「說服」遵循流程
```

**優點**：
- 更自然、用戶體驗好
- 更彈性，可適應特殊情況

**缺點**：
- Claude 可能忽略引導（Issue #73: ralplan skips critic）
- 需要持續調整語言強度

## OMC 遇到的問題

### Issue #73: ralplan 跳過 critic agent

**問題**：ExitPlanMode 被過早觸發，critic review 被跳過

**解決方案（PR #76）**：
1. 添加 `(CRITICAL)` 標記
2. 添加 logging markers：`[RALPLAN] Critic review required before approval`
3. 明確的依賴聲明

### 經驗教訓

即使引導寫得很清楚，Claude 仍可能：
- 誤判時機，提前觸發下一步
- 忽略某些步驟
- 對「mandatory」一詞理解不同

## claude-workflow 的設計決策

採用「混合策略」：

| 情境 | 方法 |
|------|------|
| 安全關鍵點（D 跳到 T） | 阻擋 |
| 最佳實踐（輸出格式） | 引導 |

### 我們的優勢

1. **Hook 阻擋**：workflow-gate.sh 確保 D→R→T 順序
2. **Agent 輸出格式**：第一行/最後一行強制格式
3. **系統追蹤**：agent-status-display.sh 自動記錄狀態

## 加強引導的技術

### 1. Skill 強調語言

```markdown
## ⚠️ (CRITICAL) 標題

**MANDATORY**: 你 **MUST** 執行...

❌ 禁止：
- 具體禁止行為

✅ 必須：
- 具體必須行為
```

### 2. Logging Markers

要求 Claude 輸出特定格式作為「執行證據」：

```
[DRT] 🔍 REVIEWER 開始審查
[DRT] ✓ 1/6 功能正確性
[DRT] 結論: APPROVE
```

### 3. Hook 動態注入

```bash
# 偵測關鍵字後注入提醒
if echo "$PROMPT" | grep -qiE "完成|done"; then
    echo '{"result": "⚠️ 提醒：確認已完成 D→R→T 流程", "continue": true}'
fi
```

## 參考資料

- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode)
- [Anthropic: Building Effective Agents](https://www.anthropic.com/research/building-effective-agents)
- Issue #73: ralplan skips critic agent execution
- PR #76: Fix for critic execution

## v0.7 控制機制簡化優化

### 設計理念：最小必要阻擋

v0.7 版本重新審視了控制層級設計，採用「**最小必要阻擋**」原則：

| 層級 | 機制 | 適用對象 |
|------|------|----------|
| Layer 1: 硬阻擋 | tools 白名單 | 所有 Agent |
| Layer 2: 引導 | Skill + Prompt | 流程與行為 |
| Layer 3: 驗證 | Hook 檢查 | 輸出格式 |

### 核心變更：移除 disallowedTools

**之前 (v0.6 及更早)**：
```yaml
name: reviewer
tools:
  - Read
  - Glob
  - Grep
disallowedTools:
  - Write
  - Edit
  - Bash
  - Task
```

**之後 (v0.7)**：
```yaml
name: reviewer
tools:
  - Read
  - Glob
  - Grep
# 不再需要 disallowedTools，白名單本身已經足夠
```

### 為什麼移除？

#### 1. 冗餘設計

```
tools: [Read, Glob, Grep]  ← 白名單本身已經「禁止」其他工具
disallowedTools: [Write, Edit, Bash, Task]  ← 多餘的黑名單
```

Claude Code Plugin 的工具權限機制：
- 只有在 `tools:` 中列出的工具才能使用
- 未列出的工具自動不可用
- 不需要額外的黑名單來「重複禁止」

#### 2. 維護負擔

每次新增工具到系統時，需要同步更新：
- ❌ 需要檢查每個 Agent 的 disallowedTools
- ❌ 容易遺漏更新
- ✅ 只需關注白名單即可

#### 3. 語意清晰

```markdown
# ✅ 清晰：這個 Agent 可以做什麼
tools: [Read, Glob, Grep]

# ❌ 冗餘：重複說明不能做什麼（已經隱含在白名單中）
disallowedTools: [Write, Edit, Bash, Task]
```

### 控制層級對比

| Agent | v0.6 | v0.7 | 簡化效果 |
|-------|------|------|----------|
| REVIEWER | tools + disallowedTools | 僅 tools | -4 行配置 |
| TESTER | tools + disallowedTools | 僅 tools | -3 行配置 |
| DEBUGGER | tools + disallowedTools | 僅 tools | -2 行配置 |

### 設計權衡：安全性 vs 便利性

```
        v0.5              v0.6                  v0.7
        ────              ────                  ────
         │                 │                     │
安全性   ██████████        ████████████          ██████████
便利性   ████              ██████                ████████

         極嚴格            過度嚴格              平衡
```

#### v0.5 的問題
- 過度阻擋，連 Main Agent 都無法執行常見操作
- 用戶體驗差

#### v0.6 的過度設計
- 雙層黑名單（tools 白名單 + disallowedTools 黑名單）
- 維護複雜

#### v0.7 的平衡
- **保留**：D→R→T 流程保護（Hook 阻擋違規路徑）
- **簡化**：移除冗餘的 disallowedTools
- **放寬**：允許所有讀取操作，只阻擋寫入核心程式碼

### 實際效果

#### 仍然被保護的路徑
```
❌ DEVELOPER 跳過 REVIEWER 直接測試
    → workflow-gate.sh 阻擋

❌ Main Agent 修改核心程式碼（保護目錄）
    → global-workflow-guard.sh 阻擋

❌ REVIEWER 嘗試修改程式碼
    → tools 白名單阻擋（無 Write/Edit）
```

#### 被允許的操作
```
✅ Main Agent 執行 git 操作
    → 白名單包含 Bash

✅ Main Agent 修改文檔檔案
    → 不在保護目錄中

✅ 所有 Agent 讀取任何檔案
    → Read 工具不受限
```

### 結論

v0.7 證明了「**好的設計是刪除不必要的部分**」：

- ✅ **更簡單**：移除冗餘配置
- ✅ **更清晰**：語意明確
- ✅ **更易維護**：減少同步點
- ✅ **同樣安全**：核心保護機制不變

**核心洞察**：
> 安全性來自白名單，不需要額外的黑名單來「重複禁止」。專注於「允許什麼」，而非「禁止什麼」。

## 更新記錄

- 2026-01-31: 新增 v0.7 控制機制簡化優化章節
- 2026-01-30: 初版，基於 OMC 對比分析
