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

## 更新記錄

- 2026-01-30: 初版，基於 OMC 對比分析
