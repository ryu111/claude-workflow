# 高風險變更範例

## 場景

修改用戶密碼重設功能，增加 OTP 雙重驗證。

## 風險評估

### 評估表

| 檢查項目 | 是/否 | 備註 |
|----------|:-----:|------|
| 修改核心邏輯（認證/支付/安全）| ✅ | 認證相關 |
| 修改多個檔案（> 5 個）| ✅ | 6 個檔案 |
| 修改公開 API | ✅ | 新增 /verify-otp endpoint |
| 修改資料庫 schema | ✅ | 新增 otp_codes 表 |
| 刪除現有功能 | ❌ | |
| 影響外部整合 | ✅ | 需要 SMS 服務 |

### 風險等級判定

**風險等級**: 🔴 HIGH

**判定依據**:
1. 涉及認證核心邏輯
2. 修改 6 個檔案
3. 新增公開 API endpoint
4. 新增資料庫表

---

## 完整流程執行

### Phase 1: DEVELOPER 實作

```markdown
## 💻 DEVELOPER 開始實作

### 實作項目
1. 建立 OTP 生成服務
2. 建立 OTP 驗證邏輯
3. 修改密碼重設流程
4. 新增資料庫 migration
5. 整合 SMS 發送服務
6. 更新 API 文檔

### 完成檔案
- src/services/otp.ts (新增)
- src/services/auth.ts (修改)
- src/routes/auth.ts (修改)
- src/migrations/20240101_add_otp_table.sql (新增)
- src/integrations/sms.ts (新增)
- docs/api/auth.md (修改)
```

### Phase 2: REVIEWER 深度審查

```markdown
## 🔍 REVIEWER 深度審查報告

### 安全性審查
- [x] OTP 生成使用 crypto 安全隨機
- [x] OTP 有效期限制（5 分鐘）
- [x] OTP 嘗試次數限制（5 次）
- [x] 使用完即失效
- [x] Rate limiting 防止暴力破解
- [x] 日誌不包含 OTP 明文

### 正確性審查
- [x] 流程邏輯正確
- [x] 錯誤處理完整
- [x] 邊界情況處理
- [x] Rollback 機制存在

### 效能審查
- [x] 資料庫查詢有索引
- [x] SMS 呼叫非同步
- [x] 無 N+1 問題

### 審查結果
**決定**: ✅ APPROVE

**建議（Minor）**:
1. 考慮加入 backup SMS provider
2. OTP 長度可配置化
```

### Phase 3: TESTER 完整測試

```markdown
## 🧪 TESTER 完整測試報告

### 測試範圍

#### Unit Tests
- [x] OTP 生成唯一性測試
- [x] OTP 過期測試
- [x] OTP 次數限制測試
- [x] OTP 驗證成功測試
- [x] OTP 驗證失敗測試

#### Integration Tests
- [x] 完整密碼重設流程
- [x] SMS 發送整合（mock）
- [x] API endpoint 測試
- [x] 資料庫事務測試

#### Security Tests
- [x] 暴力破解防護測試
- [x] Rate limiting 測試
- [x] Timing attack 防護測試

#### Edge Cases
- [x] 連續請求 OTP
- [x] 過期後重新請求
- [x] 多設備同時驗證
- [x] 網路中斷恢復

### 測試結果
**總測試數**: 28
**通過**: 28 ✅ (100%)
**失敗**: 0 ❌ (0%)
**覆蓋率**: 95%

**決定**: ✅ PASS
```

### Phase 4: 人工確認

```markdown
## 👤 人工確認請求

### 變更摘要
**功能**: 密碼重設增加 OTP 雙重驗證
**風險等級**: 🔴 HIGH

### 已完成審查
- ✅ DEVELOPER 完成實作
- ✅ REVIEWER 深度審查通過
- ✅ TESTER 完整測試通過

### 關鍵決策
1. OTP 有效期：5 分鐘
2. 最大嘗試次數：5 次
3. OTP 長度：6 位數字

### Rollback 計劃
如果需要回滾：
1. 還原 auth.ts 到之前版本
2. 執行反向 migration
3. 通知用戶暫時無法使用密碼重設

### 部署策略
建議使用 Feature Flag 漸進式部署：
1. 先對 5% 用戶啟用
2. 監控錯誤率和完成率
3. 逐步擴大到 100%

### 請確認
- [ ] 已審閱變更內容
- [ ] 已確認 Rollback 計劃
- [ ] 已同意部署策略
- [ ] 批准部署

請回覆 "APPROVE" 或提出問題。
```

---

## 流程時間軸

```
10:00  🔴 風險評估完成 - HIGH RISK
10:05  💻 DEVELOPER 開始實作
11:30  💻 DEVELOPER 完成
11:35  🔍 REVIEWER 開始深度審查
12:15  🔍 REVIEWER APPROVE
12:20  🧪 TESTER 開始完整測試
13:30  🧪 TESTER PASS
13:35  👤 請求人工確認
14:00  👤 人工確認 APPROVE
14:05  ✅ 任務完成，準備部署
```

---

## 關鍵學習點

### 為什麼需要 HIGH RISK 流程

1. **深度審查** - 比標準審查更仔細，包含安全性分析
2. **完整測試** - 不只是功能測試，還有安全測試和邊界測試
3. **人工確認** - 確保關鍵決策有人類最終把關
4. **Rollback 計劃** - 出問題時能快速恢復

### 如果跳過任何步驟

| 跳過的步驟 | 可能後果 |
|------------|----------|
| 深度審查 | 安全漏洞未被發現 |
| 完整測試 | 邊界情況導致生產事故 |
| 人工確認 | 重大決策沒有問責 |
| Rollback 計劃 | 出問題時恢復時間過長 |
