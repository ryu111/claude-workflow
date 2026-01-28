---
name: loop
description: |
  Loop 持續執行模式。自動載入於 /loop 命令觸發時。
  提供強制持續執行的指引，確保任務自動完成不中斷。
  觸發詞：loop, 持續, 繼續, 自動完成, 做到完
user-invocable: false
disable-model-invocation: false
---

# Loop 持續執行 Skill

## 核心原則

Loop 模式的目標是 **無中斷自動完成所有任務**。

### 強制執行規則

| 規則 | 說明 | 違反後果 |
|------|------|----------|
| 🚫 禁止詢問 | 完成一個任務後**不得**問「是否繼續」 | Loop 中斷，需重新啟動 |
| ⚡ 立即繼續 | 任務完成後**立即**開始下一個 | 浪費時間，降低效率 |
| 🔄 持續到完 | 必須執行到所有任務完成 | 任務不完整 |
| 🎯 聚焦任務 | 不做任務清單外的事 | 偏離目標 |

## 執行流程

```
┌─────────────────────────────────────┐
│           Loop 開始                  │
└────────────────┬────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│  讀取 tasks.md / TodoList            │
│  找到第一個 [ ] 未完成任務            │
└────────────────┬────────────────────┘
                 ↓
           有任務? ─── 否 ──→ 🎉 完成！
                 │
                是
                 ↓
┌─────────────────────────────────────┐
│  委派給對應 Agent（Task 工具）        │
│  DEVELOPER / REVIEWER / TESTER      │
└────────────────┬────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│  等待 D→R→T 流程完成                 │
└────────────────┬────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│  更新任務狀態 [ ] → [x]              │
└────────────────┬────────────────────┘
                 ↓
        ⚠️ 不詢問，直接回到頂部 ↑
```

## 並行執行支援

當 tasks.md 中的 Phase 標記為 `(parallel)` 時：

### 自動並行判定

```
## 2. Core Services (parallel)
- [ ] 2.1 建立 UserService | agent: developer | files: src/user.ts
- [ ] 2.2 建立 ProductService | agent: developer | files: src/product.ts
- [ ] 2.3 建立 OrderService | agent: developer | files: src/order.ts
```

### 執行方式

1. **檢測** `(parallel)` 標記
2. **確認** 任務間無依賴（不同檔案、不同模組）
3. **同時啟動** 多個 Task 工具呼叫（單一訊息）
4. **等待全部** 完成後進入下一 Phase

### 範例

```python
# 並行啟動 3 個 DEVELOPER
## ⚡ 並行執行 Phase 2 (3 個任務)

Task(subagent_type='developer', prompt='執行 Task 2.1: 建立 UserService')
Task(subagent_type='developer', prompt='執行 Task 2.2: 建立 ProductService')
Task(subagent_type='developer', prompt='執行 Task 2.3: 建立 OrderService')
```

## 錯誤處理

| 情況 | 處理 | 繼續執行? |
|------|------|:---------:|
| REVIEWER REJECT | 委派 DEVELOPER 修復 → 重新 D→R→T | ✅ 是 |
| TESTER FAIL | 委派 DEBUGGER → DEVELOPER 修復 | ✅ 是 |
| 連續失敗 3 次 | 暫停，報告給用戶 | ❌ 否 |
| 用戶說「暫停」| 保存進度，停止執行 | ❌ 否 |

## 中斷與恢復

### 中斷條件（僅限以下）

- 用戶明確說「暫停」「停」「中斷」
- 連續 3 次相同錯誤
- 所有任務已完成

### 恢復方式

```
/loop           # 繼續上次的執行
/loop [id]      # 指定特定 change-id
```

## 狀態追蹤

Loop 啟動時會創建 `.drt-state/.loop-active` 檔案：

```json
{"start_time":"2026-01-28T14:00:00Z","change_id":"feature-x"}
```

所有任務完成後自動刪除。

## 與其他機制的整合

| 機制 | 整合方式 |
|------|----------|
| D→R→T 流程 | Loop 中每個任務都走完整 D→R→T |
| OpenSpec | 讀取 tasks.md，更新 checkbox |
| TodoList | 可作為任務來源，自動同步 |
| E2E 測試 | 支援 --e2e 模式收集統計 |
