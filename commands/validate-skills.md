---
name: validate-skills
description: 驗證 plugin 中所有 skills 的結構、格式和引用是否正確
user-invocable: true
disable-model-invocation: true
---

# Skills 驗證

## 快速執行

執行自動化驗證腳本：

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/validate-skills.sh
```

## 驗證項目說明

執行以下驗證檢查：

## 1. 結構驗證

檢查每個 skill 目錄是否有：
- `SKILL.md` 主檔案
- 正確的 YAML frontmatter（name, description, user-invocable, disable-model-invocation）

## 2. 引用驗證

檢查 SKILL.md 中的所有相對路徑引用：
- `templates/` 下的檔案是否存在
- `references/` 下的檔案是否存在
- `examples/` 下的檔案是否存在
- `scripts/` 下的檔案是否存在

## 3. 腳本權限驗證

檢查所有 `.sh` 腳本是否有執行權限。

## 驗證步驟

請按以下步驟執行驗證：

1. **定位 skills 目錄**：查找 `skills/` 目錄

2. **對每個 skill 執行**：
   ```bash
   # 檢查 SKILL.md 存在
   test -f "${skill}/SKILL.md"

   # 檢查 YAML frontmatter
   grep -q "^name:" "${skill}/SKILL.md"
   grep -q "^description:" "${skill}/SKILL.md"
   grep -q "^user-invocable:" "${skill}/SKILL.md"
   grep -q "^disable-model-invocation:" "${skill}/SKILL.md"

   # 提取並驗證引用
   grep -oE '\]\([a-zA-Z0-9_/.-]+\)' "${skill}/SKILL.md" |
     sed 's/](\(.*\))/\1/' |
     while read link; do
       test -f "${skill}/${link}"
     done
   ```

3. **驗證腳本權限**：
   ```bash
   find skills -name "*.sh" -exec test -x {} \; -print
   ```

## 輸出格式

```markdown
## 🔍 Skills 驗證報告

### 結構驗證
| Skill | SKILL.md | Frontmatter | 狀態 |
|-------|:--------:|:-----------:|:----:|
| skill-name | ✅/❌ | ✅/❌ | ✅/❌ |

### 引用驗證
| Skill | 引用數 | 有效 | 缺失 |
|-------|:------:|:----:|:----:|
| skill-name | N | N | 0/N |

### 腳本權限
| 腳本 | 權限 |
|------|:----:|
| path/to/script.sh | ✅/❌ |

### 總結
- Skills 總數：N
- 驗證通過：N
- 需要修復：N
```

## 自動修復建議

如果發現問題，提供具體的修復指令：

- 缺少執行權限：`chmod +x path/to/script.sh`
- 缺少 frontmatter 欄位：提供範例
- 引用檔案缺失：列出缺失的檔案路徑
