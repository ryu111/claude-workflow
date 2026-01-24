# Component: [元件名稱]

## 概述

[簡短描述這個元件的用途]

---

## 結構

```
┌─────────────────────────────────────┐
│  [Container]                        │
│  ┌───────────────────────────────┐  │
│  │  [Header]                     │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │  [Content]                    │  │
│  │                               │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │  [Actions]                    │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

---

## Props / 屬性

| 屬性名 | 類型 | 必填 | 預設值 | 說明 |
|--------|------|:----:|--------|------|
| variant | `'primary' \| 'secondary'` | 否 | `'primary'` | 元件變體 |
| size | `'sm' \| 'md' \| 'lg'` | 否 | `'md'` | 元件尺寸 |
| disabled | `boolean` | 否 | `false` | 是否禁用 |

---

## 狀態

### Default
- 背景: `--color-bg-primary`
- 邊框: `1px solid --color-border`

### Hover
- 背景: `--color-bg-hover`
- 陰影: `0 2px 4px rgba(0,0,0,0.1)`

### Active / Pressed
- 背景: `--color-bg-active`
- 縮放: `scale(0.98)`

### Focus
- 邊框: `2px solid --color-primary`
- Outline: `2px solid --color-focus-ring`

### Disabled
- 透明度: `0.5`
- 游標: `not-allowed`

---

## 尺寸規格

| Size | Height | Padding | Font Size |
|------|--------|---------|-----------|
| sm | 32px | 8px 12px | 14px |
| md | 40px | 12px 16px | 16px |
| lg | 48px | 16px 24px | 18px |

---

## 響應式行為

| 斷點 | 調整 |
|------|------|
| < 576px (xs) | 全寬顯示，垂直堆疊 |
| 576-768px (sm) | [調整說明] |
| 768-992px (md) | [調整說明] |
| > 992px (lg) | 預設顯示 |

---

## 無障礙 (A11y)

- [ ] 可使用鍵盤操作 (Tab, Enter, Space)
- [ ] 有適當的 ARIA 標籤
- [ ] 顏色對比度 ≥ 4.5:1
- [ ] 點擊區域 ≥ 44x44px

---

## 使用範例

```tsx
// 基本用法
<ComponentName variant="primary" size="md">
  內容
</ComponentName>

// 禁用狀態
<ComponentName disabled>
  禁用的元件
</ComponentName>
```
