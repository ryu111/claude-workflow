---
name: validate-plugin
description: 驗證 plugin.json 配置檔案和核心目錄結構是否正確
user-invocable: true
disable-model-invocation: true
---

# Plugin 配置驗證

## 快速執行

執行自動化驗證腳本：

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/validate-plugin.sh
```

## 驗證項目說明

執行以下驗證檢查：

## 1. 檔案存在檢查

檢查 `.claude-plugin/plugin.json` 是否存在。

## 2. JSON 語法驗證

使用 `jq` 驗證 JSON 格式是否正確。

## 3. 必要欄位驗證

檢查以下欄位是否存在且非空：
- `name`：Plugin 名稱
- `version`：版本號
- `description`：Plugin 描述

## 4. 版號格式驗證

驗證 `version` 欄位是否符合 Semantic Versioning 格式：
- 標準格式：`MAJOR.MINOR.PATCH`（如 `1.0.0`, `0.5.20`）
- 支援 Pre-release：`MAJOR.MINOR.PATCH-prerelease`（如 `2.0.0-beta.1`）

## 5. 目錄結構驗證

檢查以下核心目錄是否存在：
- `agents/`：Agent 定義檔案
- `skills/`：Skill 知識目錄
- `commands/`：指令定義檔案
- `hooks/`：Hook 腳本目錄

統計每個目錄下的項目數量。

## 驗證步驟

請按以下步驟執行驗證：

1. **檢查 plugin.json**：
   ```bash
   test -f .claude-plugin/plugin.json
   ```

2. **驗證 JSON 語法**：
   ```bash
   jq empty .claude-plugin/plugin.json
   ```

3. **檢查必要欄位**：
   ```bash
   jq -r '.name' .claude-plugin/plugin.json
   jq -r '.version' .claude-plugin/plugin.json
   jq -r '.description' .claude-plugin/plugin.json
   ```

4. **驗證版號格式**：
   ```bash
   VERSION=$(jq -r '.version' .claude-plugin/plugin.json)
   [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+)?$ ]]
   ```

5. **檢查目錄結構**：
   ```bash
   test -d agents && test -d skills && test -d commands && test -d hooks
   ```

## 輸出格式

```markdown
## 🔌 Plugin 配置驗證報告

### 檔案檢查
✓ plugin.json 存在

### JSON 語法驗證
✓ JSON 語法正確

### 必要欄位驗證
✓ name: plugin-name
✓ version: 1.0.0
✓ description: Plugin description

### 版號格式驗證
✓ 版號格式正確: 1.0.0 (MAJOR=1, MINOR=0, PATCH=0)

### 目錄結構驗證
✓ agents/ (6 項目)
✓ skills/ (13 項目)
✓ commands/ (7 項目)
✓ hooks/ (13 項目)

### 欄位詳情
| 欄位 | 狀態 | 值 |
|------|:----:|-----|
| name | ✅ | `plugin-name` |
| version | ✅ | `1.0.0` |
| description | ✅ | `Plugin description` |

### 目錄詳情
| 目錄 | 狀態 | 項目數 |
|------|:----:|:------:|
| agents/ | ✅ | 6 |
| skills/ | ✅ | 13 |
| commands/ | ✅ | 7 |
| hooks/ | ✅ | 13 |

### 總結
- 驗證項目總數：10
- 驗證通過：10
- 驗證失敗：0

✅ 所有驗證通過
```

## 自動修復建議

如果發現問題，提供具體的修復指令：

- **JSON 語法錯誤**：檢查 plugin.json 格式，確保所有引號、括號、逗號正確
- **缺少必要欄位**：新增缺失的欄位：
  ```json
  {
    "name": "your-plugin-name",
    "version": "0.1.0",
    "description": "Your plugin description"
  }
  ```
- **版號格式不正確**：修正為 Semantic Versioning 格式（如 `1.0.0`）
- **目錄不存在**：建立缺失的核心目錄：
  ```bash
  mkdir -p agents skills commands hooks
  ```

## 相關指令

- `/validate-skills`：驗證 Skills 結構
- `/validate-agents`：驗證 Agents 定義
- `/validate-hooks`：驗證 Hooks 配置
