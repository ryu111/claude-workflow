# 瀏覽器測試模式與最佳實踐

## E2E 測試模式

### 1. 頁面物件模式（Page Object）

將頁面操作封裝，提高可維護性：

```bash
# 登入頁操作
login_page_fill_email() {
  agent-browser fill @email "$1"
}

login_page_fill_password() {
  agent-browser fill @password "$1"
}

login_page_submit() {
  agent-browser click @submit
}
```

### 2. 等待策略

| 策略 | 命令 | 適用場景 |
|------|------|----------|
| 等待文字 | `wait "text"` | 確認頁面載入完成 |
| 等待元素 | `snapshot -i` 後檢查 | 動態內容 |
| 固定等待 | `sleep N`（不推薦） | 最後手段 |

### 3. 截圖比對

```bash
# 基準截圖
agent-browser screenshot baseline/homepage.png

# 測試截圖
agent-browser screenshot test/homepage.png

# 比對（使用外部工具）
# pixelmatch baseline/homepage.png test/homepage.png diff.png
```

---

## 視窗尺寸標準

| 裝置類型 | 尺寸 | 命令 |
|----------|------|------|
| Desktop | 1920x1080 | `set viewport 1920 1080` |
| Laptop | 1366x768 | `set viewport 1366 768` |
| Tablet | 768x1024 | `set viewport 768 1024` |
| Mobile | 375x667 | `set viewport 375 667` |

---

## 常見陷阱與解決

| 問題 | 原因 | 解決方案 |
|------|------|----------|
| @ref 失效 | 頁面變化後 | 重新執行 `snapshot -i` |
| 元素找不到 | 動態載入 | 先 `wait "text"` |
| 點擊無效 | 元素被覆蓋 | 檢查 z-index、scroll |
| 登入狀態遺失 | 乾淨環境 | 使用 `state save/load` |

---

## 與 D→R→T 整合

### TESTER 使用流程

```
1. 取得測試案例（從 tasks.md 或 spec）
2. 選擇工具：
   - 功能測試 → agent-browser
   - 即時驗證 → claude-in-chrome
3. 執行測試
4. 截圖記錄
5. 輸出 PASS/FAIL 結果
```

### DESIGNER 使用流程

```
1. 取得設計規格
2. 使用 agent-browser（固定視窗）
3. 截圖各個狀態
4. 比對設計稿
5. 輸出差異報告
```
