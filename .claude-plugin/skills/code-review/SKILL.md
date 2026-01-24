---
name: code-review
description: |
  程式碼審查專業知識。自動載入於 REVIEWER 審查、檢查程式碼品質相關任務時。
  觸發詞：review, 審查, 檢查, code review, PR review, APPROVE, REJECT, 程式碼品質
user-invocable: false
disable-model-invocation: false
---

# 程式碼審查知識

## 審查優先順序

1. **安全性** - 最高優先
2. **正確性** - 功能是否正確
3. **效能** - 是否有效能問題
4. **可維護性** - 程式碼是否易於維護
5. **風格** - 最低優先

## 審查清單

### 安全性
- [ ] 無 SQL 注入風險（使用參數化查詢）
- [ ] 無 XSS 風險（輸出編碼）
- [ ] 無敏感資料洩露（密碼、API Key）
- [ ] 輸入驗證完整
- [ ] 適當的權限檢查

### 正確性
- [ ] 符合需求規格
- [ ] 邊界情況處理
- [ ] 空值處理
- [ ] 錯誤處理完整

### 效能
- [ ] 無 N+1 查詢
- [ ] 適當使用索引
- [ ] 無不必要的計算
- [ ] 適當的快取策略

### 可維護性
- [ ] 命名清晰有意義
- [ ] 函式單一職責
- [ ] 無重複程式碼
- [ ] 適當的註解

## 問題嚴重程度

### 🔴 Critical（必須修復）
SQL 注入、硬編碼密碼、未驗證輸入、無權限檢查

### 🟡 Important（建議修復）
N+1 查詢、魔術數字、過長函式、空的 catch block

### 🟢 Minor（可選修復）
命名不清楚、多餘的註解、格式不一致

## 回饋格式

```markdown
🔴 Critical: [問題類型]
位置: src/path/file.ts:42
問題: [具體描述]
建議: [修復方案]
```

## 決策矩陣

| 條件 | 決定 |
|------|------|
| 有 Critical 問題 | ❌ REJECT |
| 只有 Important 問題 | 🔄 REQUEST CHANGES 或 ✅ APPROVE + 建議 |
| 只有 Minor 問題 | ✅ APPROVE |
| 無問題 | ✅ APPROVE |

## 資源

### Templates

- [review-report.md](templates/review-report.md) - 審查報告範本

### References

- [security-checklist.md](references/security-checklist.md) - 安全審查清單
