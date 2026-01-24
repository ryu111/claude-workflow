---
name: debugging
description: |
  除錯專業知識。自動載入於 DEBUGGER 分析問題、測試失敗、錯誤排查相關任務時。
  觸發詞：debug, 除錯, 錯誤, error, bug, 失敗, fail, 問題, issue, 5 Whys, 根因
user-invocable: false
disable-model-invocation: false
---

# 除錯知識

## 除錯方法論

### 5 Whys 方法

```
問題：測試失敗
1. Why? → 輸出不符預期
2. Why? → 函式邏輯錯誤
3. Why? → 沒有處理邊界情況
4. Why? → 需求沒有明確說明
5. Why? → 需求收集不完整

根因：需求不完整 + 實作疏忽
```

### 二分搜尋法
當不確定問題在哪裡時，用 git bisect 或手動二分找出問題 commit。

### 最小重現
1. 移除所有非必要的程式碼
2. 只保留能重現問題的最小程式碼
3. 從最小案例開始分析

## 常見錯誤模式

### 非同步錯誤
```typescript
// ❌ 問題：忘記 await
const user = getUserById(id);  // Promise, not User
return user.name;              // undefined

// ✅ 修復
const user = await getUserById(id);
return user.name;
```

### 空值錯誤
```typescript
// ❌ 問題：未檢查空值
return user.profile.avatar;    // profile 可能是 null

// ✅ 修復
return user?.profile?.avatar ?? defaultAvatar;
```

### 型別錯誤
```typescript
// ❌ 問題：型別不匹配
const count = "10";
const total = count + 5;       // "105" 而不是 15

// ✅ 修復
const count = parseInt("10", 10);
const total = count + 5;       // 15
```

### 競態條件
使用鎖、交易或原子操作來避免。

## 錯誤訊息解讀

| 錯誤類型 | 常見原因 |
|----------|----------|
| `undefined is not a function` | 呼叫不存在的方法 |
| `Cannot read property of null` | 存取 null/undefined 的屬性 |
| `Maximum call stack exceeded` | 無限遞迴 |
| `ECONNREFUSED` | 服務未啟動或網路問題 |
| `ENOENT` | 檔案不存在 |

## 修復報告格式

```markdown
## 🐛 除錯報告

### 問題描述
[一句話描述]

### 重現步驟
1. [步驟 1]
2. [步驟 2]

### 根因分析
[詳細說明為什麼會發生]

### 修復方案
**檔案：** src/xxx.ts
**位置：** 第 XX 行
```diff
- const result = data.value;
+ const result = data?.value ?? defaultValue;
```

### 預防措施
[如何避免類似問題]
```

## 資源

### Scripts

- [analyze-error.sh](scripts/analyze-error.sh) - 錯誤分析輔助腳本

### Templates

- [debug-report.md](templates/debug-report.md) - 除錯報告範本

### References

- [common-errors.md](references/common-errors.md) - 常見錯誤參考表
