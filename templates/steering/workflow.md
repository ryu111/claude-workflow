# 工作流規則

> 此檔案定義專案的開發工作流。放置於 `.claude/steering/workflow.md`

---

## D→R→T 流程

本專案採用 **Developer → Reviewer → Tester** 流程：

```
DEVELOPER (實作) → REVIEWER (審查) → TESTER (測試)
     ↓                  ↓                ↓
   完成變更          APPROVE/REJECT     PASS/FAIL
```

### 風險等級判定

| 等級 | 條件 | 流程 |
|:----:|------|------|
| 🟢 LOW | 文檔、設定、樣式調整 | D → T（可跳過 R）|
| 🟡 MEDIUM | 一般功能、Bug 修復 | D → R → T |
| 🔴 HIGH | 安全、支付、API、資料庫 | D → R(opus) → T + 人工確認 |

### 高風險路徑

以下路徑的變更自動判定為 HIGH RISK：
- `/auth/`, `/security/`, `/payment/`
- `/api/`, `/migration/`
- `*.sql`, `*.prisma`, `Dockerfile`, `.env*`

### 高風險特徵

- 修改超過 5 個檔案
- 刪除超過 50 行程式碼
- 修改公開 API 介面

---

## 變更追蹤

使用 Change ID 追蹤每個變更：

```
[feature-login] DEVELOPER → REVIEWER → TESTER
[bugfix-auth]   DEVELOPER → REVIEWER → TESTER
```

---

## 自訂規則

<!-- 在此新增專案特定的工作流規則 -->

