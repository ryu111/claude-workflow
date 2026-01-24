# Design Tokens 參考

## 色彩系統

### 主色調

```css
/* Primary */
--color-primary-50: #E3F2FD;
--color-primary-100: #BBDEFB;
--color-primary-200: #90CAF9;
--color-primary-300: #64B5F6;
--color-primary-400: #42A5F5;
--color-primary-500: #2196F3;  /* 主色 */
--color-primary-600: #1E88E5;
--color-primary-700: #1976D2;
--color-primary-800: #1565C0;
--color-primary-900: #0D47A1;
```

### 語意色

```css
/* Success */
--color-success: #4CAF50;
--color-success-light: #81C784;
--color-success-dark: #388E3C;

/* Warning */
--color-warning: #FF9800;
--color-warning-light: #FFB74D;
--color-warning-dark: #F57C00;

/* Error */
--color-error: #F44336;
--color-error-light: #E57373;
--color-error-dark: #D32F2F;

/* Info */
--color-info: #2196F3;
--color-info-light: #64B5F6;
--color-info-dark: #1976D2;
```

### 中性色

```css
/* Gray Scale */
--color-gray-50: #FAFAFA;
--color-gray-100: #F5F5F5;
--color-gray-200: #EEEEEE;
--color-gray-300: #E0E0E0;
--color-gray-400: #BDBDBD;
--color-gray-500: #9E9E9E;
--color-gray-600: #757575;
--color-gray-700: #616161;
--color-gray-800: #424242;
--color-gray-900: #212121;
```

---

## 間距系統 (8px Grid)

```css
--space-0: 0;
--space-1: 4px;   /* 0.5x */
--space-2: 8px;   /* 1x - 基礎單位 */
--space-3: 12px;  /* 1.5x */
--space-4: 16px;  /* 2x */
--space-5: 20px;  /* 2.5x */
--space-6: 24px;  /* 3x */
--space-8: 32px;  /* 4x */
--space-10: 40px; /* 5x */
--space-12: 48px; /* 6x */
--space-16: 64px; /* 8x */
```

---

## 字體系統

### 字體家族

```css
--font-family-sans: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
--font-family-mono: 'JetBrains Mono', 'Fira Code', monospace;
```

### 字體大小

```css
--font-size-xs: 12px;   /* 說明文字 */
--font-size-sm: 14px;   /* 次要文字 */
--font-size-md: 16px;   /* 基礎文字 */
--font-size-lg: 18px;   /* 大文字 */
--font-size-xl: 20px;   /* 小標題 */
--font-size-2xl: 24px;  /* 標題 */
--font-size-3xl: 30px;  /* 大標題 */
--font-size-4xl: 36px;  /* 頁面標題 */
```

### 字重

```css
--font-weight-normal: 400;
--font-weight-medium: 500;
--font-weight-semibold: 600;
--font-weight-bold: 700;
```

### 行高

```css
--line-height-tight: 1.25;
--line-height-normal: 1.5;
--line-height-relaxed: 1.75;
```

---

## 圓角

```css
--radius-none: 0;
--radius-sm: 4px;
--radius-md: 8px;
--radius-lg: 12px;
--radius-xl: 16px;
--radius-full: 9999px;  /* 圓形 */
```

---

## 陰影

```css
--shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.05);
--shadow-md: 0 4px 6px rgba(0, 0, 0, 0.1);
--shadow-lg: 0 10px 15px rgba(0, 0, 0, 0.1);
--shadow-xl: 0 20px 25px rgba(0, 0, 0, 0.15);
```

---

## 過渡動畫

```css
--transition-fast: 150ms ease;
--transition-normal: 250ms ease;
--transition-slow: 350ms ease;
```

---

## Z-Index 層級

```css
--z-dropdown: 1000;
--z-sticky: 1020;
--z-fixed: 1030;
--z-modal-backdrop: 1040;
--z-modal: 1050;
--z-popover: 1060;
--z-tooltip: 1070;
```

---

## 斷點

```css
--breakpoint-xs: 0;
--breakpoint-sm: 576px;
--breakpoint-md: 768px;
--breakpoint-lg: 992px;
--breakpoint-xl: 1200px;
--breakpoint-xxl: 1400px;
```
