# global-workflow-guard.sh 白名單修復總結

## 修復日期
2026-01-27

## 問題描述

### 1. Plugin 腳本被阻擋
當 Main Agent 執行 `/ralph-loop` 或 `/init` 等 Command 時，觸發的 Plugin 內部腳本被 `global-workflow-guard.sh` 阻擋：

```bash
# 被阻擋的命令範例
bash ~/.claude/plugins/.../setup-ralph-loop.sh ...
bash .../init.sh
```

**原因**：守衛腳本沒有識別 Plugin 內部腳本的白名單機制。

### 2. 白名單不夠完整
現有的 `READONLY_PATTERNS` 缺少常用的唯讀命令：
- 更多 git 命令（如 `git rev-list`, `git describe`, `git shortlog`）
- 測試相關命令（如 `go test`, `cargo test`）
- 格式化檢查（如 `prettier --check`, `black --check`, `ruff check`）
- 環境資訊命令（如 `env`, `printenv`, `go version`, `cargo --version`, `rustc --version`）
- 搜尋工具（如 `rg`, `ag`, `yq`）

## 修復方案

### A. 新增 Plugin 腳本白名單區塊

在 Bash 命令檢查中，**在危險操作符檢查之前**加入 Plugin 腳本白名單：

```bash
# ═══════════════════════════════════════════════════════════════
# Plugin 腳本白名單（允許 Plugin 內部腳本執行）
# ═══════════════════════════════════════════════════════════════

# 允許來自 Plugin 目錄的腳本（Command 的 allowed-tools 授權）
PLUGIN_SCRIPT_PATTERNS=(
    # ralph-wiggum plugin
    "\\.claude/plugins/.*/ralph-wiggum.*/setup-ralph-loop\\.sh"
    # claude-workflow plugin
    "claude-workflow.*/scripts/init\\.sh"
    "claude-workflow.*/scripts/validate-.*\\.sh"
)

is_plugin_script() {
    local cmd="$1"
    for pattern in "${PLUGIN_SCRIPT_PATTERNS[@]}"; do
        if echo "$cmd" | grep -qE "$pattern"; then
            return 0
        fi
    done
    return 1
}

# 檢查是否為 Plugin 腳本
if is_plugin_script "$COMMAND"; then
    echo "[$(date)] Plugin script allowed: $COMMAND" >> "$DEBUG_LOG"
    exit 0
fi
```

### B. 擴展 READONLY_PATTERNS

將第 94 行的白名單擴展為：

```bash
READONLY_PATTERNS="^(git (status|log|diff|branch|show|remote|rev-parse|ls-files|blame|tag|config --get|rev-list|describe|shortlog)|ls|pwd|cat|head|tail|wc|grep|rg|ag|find|which|file|stat|du|df|date|uname|whoami|hostname|env|printenv|node --version|npm --version|npm list|npm ls|python --version|pip --version|pip list|pip show|go version|cargo --version|rustc --version|jq|yq|npm (test|run test|run lint|run check)|npx |yarn (test|lint)|pytest|python -m pytest|go test|cargo test|make test|prettier --check|eslint --print-config|black --check|ruff check)"
```

**新增命令分類**：

| 分類 | 新增命令 |
|------|----------|
| Git | `rev-list`, `describe`, `shortlog` |
| 測試 | `go test`, `cargo test`, `make test` |
| 格式化檢查 | `prettier --check`, `black --check`, `ruff check` |
| Linter 配置 | `eslint --print-config` |
| 環境資訊 | `env`, `printenv`, `go version`, `cargo --version`, `rustc --version` |
| 搜尋工具 | `rg`, `ag`, `yq` |
| npm 腳本 | `npm run lint`, `npm run check` |
| yarn 腳本 | `yarn lint` |

### C. 檢查邏輯順序

確保檢查順序正確，以提高效能並確保安全：

```
1. Bypass 檢查（環境變數、配置文件）
2. 工具名稱解析
3. Subagent 檢查
4. 【新增】Plugin 腳本白名單 ⭐
5. 危險操作符檢查（>, >>, |, tee, `, $()）
6. READONLY_PATTERNS 白名單
7. 阻擋決策
```

## 測試驗證

### 測試腳本
`tests/scripts/test-plugin-script-whitelist.sh`

### 測試結果
```
總測試數: 26
✓ 通過: 26
✗ 失敗: 0

✓ 所有測試通過！
```

### 測試覆蓋範圍

#### Plugin 腳本白名單測試（4 個）
- ✅ ralph-wiggum `setup-ralph-loop.sh`
- ✅ claude-workflow `init.sh`
- ✅ claude-workflow `validate-agents.sh`
- ✅ claude-workflow `validate-skills.sh`

#### 擴展的 Git 命令測試（3 個）
- ✅ `git rev-list HEAD~5..HEAD`
- ✅ `git describe --tags --abbrev=0`
- ✅ `git shortlog -s -n`

#### 測試與格式化命令測試（7 個）
- ✅ `npm run lint`
- ✅ `npm run check`
- ✅ `prettier --check src/`
- ✅ `black --check .`
- ✅ `ruff check src/`
- ✅ `go test ./...`
- ✅ `cargo test --all`

#### 環境資訊命令測試（5 個）
- ✅ `env`
- ✅ `printenv PATH`
- ✅ `go version`
- ✅ `cargo --version`
- ✅ `rustc --version`

#### 搜尋工具命令測試（3 個）
- ✅ `rg 'pattern' src/`
- ✅ `ag 'pattern' src/`
- ✅ `yq eval '.version' config.yaml`

#### 危險命令阻擋測試（4 個）
- ✅ `rm -rf /tmp/test` → 阻擋
- ✅ `echo 'test' > file.txt` → 阻擋
- ✅ `cat file | tee output.txt` → 阻擋
- ✅ `echo $(whoami)` → 阻擋

## 預期行為

### 現在應該被允許的命令

```bash
# ✅ Plugin 腳本
bash ~/.claude/plugins/cache/ralph-wiggum/ralph-wiggum/1.0.0/setup-ralph-loop.sh
bash ~/projects/claude-workflow/scripts/init.sh
bash ~/projects/claude-workflow/scripts/validate-agents.sh

# ✅ 擴展的 Git 命令
git rev-list HEAD~5..HEAD
git describe --tags
git shortlog -s -n

# ✅ 測試與格式化檢查
npm run lint
npm run check
prettier --check src/
black --check .
ruff check src/
go test ./...
cargo test --all

# ✅ 環境資訊
env
printenv PATH
go version
cargo --version
rustc --version

# ✅ 搜尋工具
rg 'pattern' src/
ag 'pattern' src/
yq eval '.version' config.yaml
```

### 仍然應該被阻擋的命令

```bash
# ❌ 危險操作符
rm -rf /
echo "test" > file.txt
cat file | tee output.txt
echo $(whoami)

# ❌ 寫入操作（非唯讀）
npm install package
pip install package
git commit -m "message"
git push
```

## 安全考量

### Plugin 腳本白名單的安全性

1. **路徑限制**：只允許特定路徑下的 Plugin 腳本
2. **Command 授權**：Plugin 的 Command 必須在 `allowed-tools` 中明確宣告 `Bash` 權限
3. **正規表達式匹配**：使用精確的正規表達式避免路徑遍歷攻擊

### 唯讀命令白名單的安全性

1. **危險操作符檢查優先**：即使命令在白名單中，包含 `>`, `>>`, `|`, `tee`, `` ` ``, `$()` 等操作符仍會被阻擋
2. **前綴匹配**：使用 `^` 確保從命令開頭匹配，避免繞過
3. **明確指定子命令**：如 `git (status|log|...)` 而非 `git .*`

## 維護指南

### 如何新增 Plugin 腳本白名單

在 `PLUGIN_SCRIPT_PATTERNS` 陣列中加入新的正規表達式：

```bash
PLUGIN_SCRIPT_PATTERNS=(
    # 現有的 patterns...
    # 你的新 Plugin
    "your-plugin.*/scripts/your-script\\.sh"
)
```

### 如何新增唯讀命令白名單

在 `READONLY_PATTERNS` 的括號內加入新的命令模式（使用 `|` 分隔）：

```bash
READONLY_PATTERNS="^(git (status|...)|your-new-command|...)"
```

**注意事項**：
1. 確保命令是**完全唯讀**的
2. 不要加入任何可能修改系統狀態的命令
3. 測試新增的命令是否會被危險操作符檢查阻擋

## 相關檔案

- `hooks/scripts/global-workflow-guard.sh` - 守衛腳本主檔
- `tests/scripts/test-plugin-script-whitelist.sh` - 測試腳本
- `docs/whitelist-fix-summary.md` - 本文件

## 附註

此修復確保 Plugin 系統可以正常運作，同時保持 D→R→T 工作流的安全性。所有 Plugin 腳本必須：

1. 在 Plugin 目錄下（`.claude/plugins/` 或專案目錄下的 Plugin）
2. 符合白名單的正規表達式
3. 由有 `Bash` 權限的 Command 調用

這樣可以平衡功能性與安全性。
