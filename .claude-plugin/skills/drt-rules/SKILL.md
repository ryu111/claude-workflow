---
name: drt-rules
description: |
  D→R→T 工作流核心規則。自動載入於程式碼變更、開發、審查、測試相關任務。
  觸發詞：D→R→T, Developer, Reviewer, Tester, 流程, workflow, code change, 程式碼變更, APPROVE, REJECT, PASS, FAIL
user-invocable: false
disable-model-invocation: false
---

# D→R→T 工作流規則

## 核心原則

**風險導向**：流程強度應與變更風險成正比。

## 變更風險分級

### 🟢 LOW RISK - 快速通道

**適用範圍：**
- 文檔變更：`*.md`, `*.txt`, `README`, `CHANGELOG`
- 配置調整：`*.json`, `*.yaml`, `*.toml`（非敏感配置）
- 格式修正：空白、縮排、註解修改
- 重命名：變數名、檔案名（無邏輯變更）
- 刪除未使用的程式碼

**流程：**
```
DEVELOPER ─────► 自動驗證 ─────► 完成
    │                │
    ▼                ▼
  實作變更      格式/語法檢查
```

**自動驗證項目：**
- 語法正確性
- 格式符合規範
- 無破壞性變更

### 🟡 MEDIUM RISK - 標準流程

**適用範圍：**
- 新增功能：不影響現有邏輯
- Bug 修復：範圍明確、影響有限
- 單檔案修改：< 100 行變更
- 測試檔案修改
- 內部工具調整

**流程：**
```
DEVELOPER ─────► REVIEWER ─────► TESTER
    │                │               │
    ▼                ▼               ▼
  實作程式碼     APPROVE/REJECT   PASS/FAIL
```

### 🔴 HIGH RISK - 強化流程

**適用範圍：**
- 核心邏輯變更：認證、支付、權限、安全相關
- 跨模組修改：影響多個檔案或模組
- API 變更：對外介面、合約修改
- 資料庫變更：schema、migration
- 依賴更新：主要版本升級
- 刪除功能：移除現有功能

**流程：**
```
DEVELOPER ─► REVIEWER ─► TESTER ─► 人工確認
    │            │           │          │
    ▼            ▼           ▼          ▼
  實作      深度審查    完整測試    最終核准
```

**強化審查項目：**
- 安全性分析
- 效能影響評估
- 向後相容性檢查
- 回滾計劃

## 流程轉換規則

| 當前階段 | 結果 | 下一步 |
|----------|------|--------|
| DEVELOPER | 完成 (LOW) | → 自動驗證 → 完成 |
| DEVELOPER | 完成 (MEDIUM/HIGH) | → REVIEWER |
| REVIEWER | APPROVE | → TESTER |
| REVIEWER | APPROVE + MINOR | → TESTER（附帶建議） |
| REVIEWER | REJECT | → DEVELOPER（附帶修改要求） |
| TESTER | PASS | → 完成 / 人工確認 (HIGH) |
| TESTER | FAIL | → DEBUGGER → DEVELOPER |

## 合法路徑總覽

| 風險等級 | 路徑 | 適用場景 |
|----------|------|----------|
| 🟢 LOW | D → 自動驗證 → 完成 | 文檔、配置、格式 |
| 🟡 MEDIUM | D → R → T → 完成 | 一般開發 |
| 🟡 MEDIUM | Design → D → R → T | UI 相關 |
| 🔴 HIGH | D → R(深度) → T(完整) → 人工確認 | 核心變更 |

## 風險判定規則

### 自動升級為 HIGH RISK

以下情況自動視為高風險：

```
檔案路徑包含：
- /auth/, /security/, /payment/
- /api/, /public/
- /migration/, /schema/

檔案類型：
- *.sql, *.prisma (資料庫)
- Dockerfile, *.yml (CI/CD)
- .env*, secrets* (敏感配置)

變更特徵：
- 修改 > 5 個檔案
- 刪除 > 50 行程式碼
- 修改公開 API 簽名
```

### 允許降級的情況

**MEDIUM → LOW（需明確標註）：**
- 修復已知的格式問題
- 更新依賴的 patch 版本
- 新增測試案例（不修改原始碼）

## 快速通道使用條件

使用快速通道時，DEVELOPER 必須在輸出中聲明：

```markdown
## 💨 快速通道

**風險等級：** 🟢 LOW
**理由：** [為什麼是低風險]
**變更類型：** [文檔/配置/格式/重命名]
**自動驗證：** ✅ 通過
```

## 重試機制

| 風險等級 | 最大重試次數 | BLOCKED 後處理 |
|----------|--------------|----------------|
| 🟢 LOW | 1 次 | 升級為 MEDIUM |
| 🟡 MEDIUM | 3 次 | 等待用戶介入 |
| 🔴 HIGH | 2 次 | 暫停 + 通知用戶 |

## 禁止行為

### 絕對禁止
```
❌ HIGH RISK 變更走快速通道
❌ 跳過 REVIEWER 直接測試（MEDIUM/HIGH）
❌ TESTER 失敗後不經 DEBUGGER 直接修改
❌ 隱瞞變更的真實風險等級
```

### 禁止硬編碼

所有字串常數必須使用語言特性定義，詳見 [hard-coding-rules.md](references/hard-coding-rules.md)。

## 發現即修復原則

在任何階段發現問題，立即修復：

- 發現 bug → 立即修復（即使不在當前任務範圍）
- 發現安全問題 → 最高優先處理（自動升級為 HIGH RISK）
- 發現技術債 → 記錄或立即處理

## 誠實原則

- 不確定風險等級時，選擇較高等級
- 做不到時說「做不到」
- 有問題時立即報告，不隱瞞

## 資源

### Templates

- [risk-assessment.md](templates/risk-assessment.md) - 風險評估範本

### References

- [hard-coding-rules.md](references/hard-coding-rules.md) - 禁止硬編碼規則

### Examples

- [high-risk-change.md](examples/high-risk-change.md) - 高風險變更完整範例
