---
name: ui-design
description: |
  UI/UX 設計知識。自動載入於 DESIGNER 設計介面或 DEVELOPER 實作 UI 相關任務時。
  觸發詞：design, 設計, UI, UX, 介面, interface, 響應式, responsive, 元件, component, CSS
user-invocable: false
disable-model-invocation: false
---

# UI/UX 設計知識

## 設計原則

### 視覺層次
1. **大小** - 重要的元素更大
2. **顏色** - 使用對比突出重點
3. **位置** - 重要內容放在視覺焦點
4. **空間** - 用留白分組相關內容

### 一致性
- 相同功能使用相同樣式
- 間距使用 4px 或 8px 的倍數
- 色彩使用預定義的調色盤
- 字體使用預定義的字體系統

### 可及性 (Accessibility)
- 顏色對比度至少 4.5:1
- 可點擊區域至少 44x44px
- 支援鍵盤導航
- 提供適當的 ARIA 標籤

## 元件設計規格

### 按鈕尺寸
- Large: height 48px, padding 24px
- Medium: height 40px, padding 16px (default)
- Small: height 32px, padding 12px

### 按鈕變體
- Primary: 主要行動，實心背景
- Secondary: 次要行動，邊框樣式
- Tertiary: 低優先，僅文字

### 表單輸入狀態
- Default: 灰色邊框
- Focus: 主色邊框 + 陰影
- Error: 紅色邊框 + 錯誤訊息
- Disabled: 灰色背景，不可編輯

## 響應式設計

### 斷點

| 名稱 | 寬度 | 典型裝置 |
|------|------|----------|
| xs | < 576px | 手機 |
| sm | 576-767px | 大型手機 |
| md | 768-991px | 平板 |
| lg | 992-1199px | 小型桌面 |
| xl | ≥ 1200px | 桌面 |

### Mobile First 策略
1. 先設計手機版
2. 漸進增強到平板
3. 最後優化桌面版

## 設計 Tokens（範本）

專案應根據品牌需求自訂這些值：

```css
/* 主色 - 根據專案自訂 */
--color-primary: #0066CC;

/* 語意色 */
--color-success: #28A745;
--color-warning: #FFC107;
--color-error: #DC3545;

/* 間距系統 */
--space-1: 4px;
--space-2: 8px;
--space-4: 16px;
--space-6: 32px;

/* 字體大小 */
--font-size-sm: 14px;
--font-size-md: 16px;
--font-size-lg: 18px;
```

## 資源

### Templates

- [component-spec.md](templates/component-spec.md) - UI 元件規格文件範本

### References

- [design-tokens.md](references/design-tokens.md) - 完整的 Design Tokens 參考
