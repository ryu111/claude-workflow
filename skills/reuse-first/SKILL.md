---
name: reuse-first
description: |
  強制執行「不重複造輪子」原則。自動載入於 ARCHITECT 和 DEVELOPER 在規劃、實作任何新功能時。
  觸發詞：規劃, 實作, 開發, 新功能, 函式, 工具, 元件, 模組
user-invocable: false
disable-model-invocation: false
---

# Reuse First - 複用優先原則

## 核心原則

1. **先找後寫**：實作任何功能前，必須先檢查現有資源
2. **發現即抽取**：發現重複程式碼時，必須抽取為共用功能

## 強制檢查清單

### ARCHITECT 規劃時（必須）

在建立 tasks.md 前，必須執行：

| 步驟 | 動作 | 工具 |
|:----:|------|------|
| 1 | 搜尋專案內類似功能 | Grep, Glob |
| 2 | 檢查現有模組結構 | Read `src/`, `lib/`, `utils/` |
| 3 | 評估可複用的元件 | 記錄到規劃文件 |

**輸出要求**：
- 每個任務必須標註：`複用: [現有模組]` 或 `新建: [原因]`

### DEVELOPER 實作時（必須）

開始寫程式碼前，必須執行：

| 優先級 | 檢查項目 | 說明 |
|:------:|----------|------|
| 1 | 專案內現有程式碼 | `Grep` 搜尋類似功能名稱 |
| 2 | 已安裝的套件 | 檢查 package.json / requirements.txt |
| 3 | 語言標準庫 | 優先使用內建功能 |
| 4 | 成熟第三方套件 | 僅在必要時新增依賴 |

**搜尋指令範例**：
```bash
# 搜尋現有函式
Grep pattern="function.*formatDate|formatDate.*="
Grep pattern="def format_date|format_date"

# 搜尋現有工具
Glob pattern="**/utils/**/*.{ts,js,py}"
Glob pattern="**/helpers/**/*.{ts,js,py}"
Glob pattern="**/lib/**/*.{ts,js,py}"
```

## DRY 原則：發現即抽取

### 觸發條件

當發現以下情況時，**必須**進行抽取：

| 情況 | 動作 |
|------|------|
| 相同邏輯出現 2+ 次 | 抽取為共用函式 |
| 相似模式出現 3+ 次 | 抽取為通用工具 |
| 複製貼上程式碼 | 禁止！必須抽取 |

### 抽取位置建議

| 類型 | 建議位置 | 範例 |
|------|----------|------|
| 工具函式 | `utils/` 或 `helpers/` | formatDate, debounce |
| 共用元件 | `components/common/` | Button, Modal |
| 業務邏輯 | `services/` 或 `lib/` | AuthService |
| 類型定義 | `types/` | interfaces, enums |

### 抽取流程

```
發現重複
    ↓
1. 識別共同模式
    ↓
2. 設計通用介面
    ↓
3. 建立共用模組
    ↓
4. 替換所有使用處
    ↓
5. 測試確保功能一致
```

## 禁止行為

| 禁止 | 原因 |
|------|------|
| ❌ 直接開始寫新功能 | 必須先搜尋現有資源 |
| ❌ 複製貼上程式碼 | 違反 DRY 原則 |
| ❌ 忽略現有套件功能 | 可能重複造輪子 |
| ❌ 重複定義相同函式 | 必須抽取共用 |

## 合規檢查

REVIEWER 必須檢查：
- [ ] 是否有搜尋現有資源的證據
- [ ] 是否有不必要的重複程式碼
- [ ] 是否有可以抽取但未抽取的共用邏輯
- [ ] 是否有可以使用現有套件但自己實作的情況

## 範例

### ✅ 正確做法

```
DEVELOPER 實作前：
1. Grep "formatDate" → 找到 utils/date.ts 已有
2. 直接 import { formatDate } from '@/utils/date'
3. 不需要自己寫
```

### ❌ 錯誤做法

```
DEVELOPER 直接寫：
function formatDate(date) {
  return date.toISOString().split('T')[0]
}
// 結果 utils/date.ts 已經有一模一樣的函式
```

## 資源

### Templates

- [reuse-analysis.md](templates/reuse-analysis.md) - 複用分析範本
- [extraction-plan.md](templates/extraction-plan.md) - 程式碼抽取計劃範本

### References

- [common-patterns.md](references/common-patterns.md) - 常見可複用模式參考
