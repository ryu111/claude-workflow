# 專案結構

> 此檔案說明專案的目錄結構。放置於 `.claude/steering/structure.md`

---

## 目錄樹

```
project-root/
├── src/                    # 原始碼
│   ├── app/               # 應用程式入口
│   ├── components/        # UI 元件
│   ├── lib/               # 共用函式庫
│   ├── services/          # 業務邏輯服務
│   ├── types/             # 型別定義
│   └── utils/             # 工具函式
├── tests/                  # 測試檔案
│   ├── unit/              # 單元測試
│   ├── integration/       # 整合測試
│   └── e2e/               # 端對端測試
├── docs/                   # 文件
├── scripts/                # 腳本
├── config/                 # 配置檔案
└── .claude/                # Claude 配置
    └── steering/          # 引導檔案
        ├── workflow.md    # 工作流規則
        ├── tech.md        # 技術棧
        └── structure.md   # 專案結構（本檔案）
```

---

## 重要檔案

| 檔案 | 說明 |
|------|------|
| `package.json` | 套件依賴和腳本 |
| `tsconfig.json` | TypeScript 配置 |
| `.env` | 環境變數（不提交） |
| `.env.example` | 環境變數範例 |
| `Dockerfile` | 容器配置 |
| `docker-compose.yml` | 開發環境編排 |

---

## 命名規範

| 類型 | 格式 | 範例 |
|------|------|------|
| 元件 | PascalCase | `UserProfile.tsx` |
| 工具函式 | camelCase | `formatDate.ts` |
| 常數 | SCREAMING_SNAKE | `API_BASE_URL` |
| 測試 | *.test.ts | `user.test.ts` |
| 型別 | PascalCase + Type/Interface | `UserType` |

---

## 敏感路徑

以下路徑包含敏感邏輯，修改時需要額外審查：

| 路徑 | 說明 |
|------|------|
| `/src/auth/` | 認證邏輯 |
| `/src/payment/` | 支付處理 |
| `/src/api/` | API 端點 |
| `/migrations/` | 資料庫遷移 |

---

## 自訂說明

<!-- 在此新增專案特定的結構說明 -->

