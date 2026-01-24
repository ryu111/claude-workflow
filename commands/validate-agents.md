---
name: validate-agents
description: 驗證 plugin 中所有 agents 的結構、frontmatter 和引用
user-invocable: true
disable-model-invocation: true
---

# Agents 驗證

## 快速執行

執行自動化驗證腳本：

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/validate-agents.sh
```

## 驗證項目說明

執行以下驗證檢查：

## 1. 結構驗證

檢查每個 agent 檔案是否有：
- 完整的 YAML frontmatter（以 `---` 開始和結束）
- 必要欄位：`name`、`description`

## 2. Skills 引用驗證

檢查 frontmatter 中 `skills` 欄位引用的 skills 是否都存在於 `skills/` 目錄。

## 3. Tools 配置檢查

統計每個 agent 的：
- `tools`: 允許使用的工具清單
- `disallowedTools`: 禁止使用的工具清單

## 驗證步驟

請按以下步驟執行驗證：

1. **定位 agents 目錄**：查找 `.claude-plugin/agents/` 目錄

2. **對每個 agent 執行**：
   ```bash
   # 檢查 frontmatter 存在
   head -1 "${agent}" | grep -q "^---$"

   # 檢查必要欄位
   grep -q "^name:" "${agent}"
   grep -q "^description:" "${agent}"

   # 提取並驗證 skills 引用
   grep "^skills:" "${agent}" | \
     sed 's/^skills:\s*//' | \
     tr ',' '\n' | \
     while read skill; do
       test -d "skills/${skill}"
     done
   ```

3. **驗證腳本執行**：
   ```bash
   .claude-plugin/scripts/validate-agents.sh
   ```

## 輸出格式

```markdown
## 🤖 Agents 驗證報告

### 結構驗證
| Agent | Frontmatter | name | description | 狀態 |
|-------|:-----------:|:----:|:-----------:|:----:|
| agent-name | ✅/❌ | ✅/❌ | ✅/❌ | ✅/❌ |

### Skills 引用驗證
| Agent | 引用數 | 有效 | 缺失 |
|-------|:------:|:----:|:----:|
| agent-name | N | N | 0/N |

### Tools 配置
| Agent | 允許工具 | 禁止工具 |
|-------|:--------:|:--------:|
| agent-name | N | N |

### 總結
- Agents 總數：N
- 驗證通過：N
- 需要修復：N
```

## 自動修復建議

如果發現問題，提供具體的修復指令：

- 缺少 frontmatter：提供完整 frontmatter 範例
- 缺少必要欄位：提供欄位範例
- Skills 引用缺失：列出缺失的 skills 名稱
