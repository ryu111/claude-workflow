#!/bin/bash
# auto-format.sh - 自動格式化程式碼
# 事件: PostToolUse (Write|Edit)
# 功能: 檔案變更後自動格式化，確保程式碼風格一致
# 2025 AI Guardrails: Post-hook Quality Assurance

# 讀取 stdin 的 JSON 輸入
INPUT=$(cat)

# 解析工具和檔案路徑
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# 如果沒有檔案路徑，退出
if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# 取得檔案副檔名
EXTENSION="${FILE_PATH##*.}"
FILENAME=$(basename "$FILE_PATH")

# 跳過不需要格式化的檔案
case "$FILENAME" in
    *.min.js|*.min.css|package-lock.json|yarn.lock|*.lock)
        exit 0
        ;;
esac

# 根據檔案類型選擇 formatter
FORMATTED=false
FORMAT_TOOL=""

case "$EXTENSION" in
    js|jsx|ts|tsx|json|css|scss|less|html|vue|svelte)
        # JavaScript/TypeScript/Web - 使用 prettier
        if command -v prettier &> /dev/null; then
            if prettier --check "$FILE_PATH" &> /dev/null; then
                # 已經格式化
                :
            else
                prettier --write "$FILE_PATH" &> /dev/null
                FORMATTED=true
                FORMAT_TOOL="prettier"
            fi
        fi
        ;;

    py)
        # Python - 使用 black 或 autopep8
        if command -v black &> /dev/null; then
            if black --check "$FILE_PATH" &> /dev/null; then
                :
            else
                black --quiet "$FILE_PATH" &> /dev/null
                FORMATTED=true
                FORMAT_TOOL="black"
            fi
        elif command -v autopep8 &> /dev/null; then
            autopep8 --in-place "$FILE_PATH" &> /dev/null
            FORMATTED=true
            FORMAT_TOOL="autopep8"
        fi
        ;;

    go)
        # Go - 使用 gofmt
        if command -v gofmt &> /dev/null; then
            gofmt -w "$FILE_PATH" &> /dev/null
            FORMATTED=true
            FORMAT_TOOL="gofmt"
        fi
        ;;

    rs)
        # Rust - 使用 rustfmt
        if command -v rustfmt &> /dev/null; then
            rustfmt "$FILE_PATH" &> /dev/null
            FORMATTED=true
            FORMAT_TOOL="rustfmt"
        fi
        ;;

    sh|bash)
        # Shell - 使用 shfmt
        if command -v shfmt &> /dev/null; then
            shfmt -w "$FILE_PATH" &> /dev/null
            FORMATTED=true
            FORMAT_TOOL="shfmt"
        fi
        ;;

    md|markdown)
        # Markdown - 使用 prettier
        if command -v prettier &> /dev/null; then
            prettier --write "$FILE_PATH" &> /dev/null 2>&1
            FORMATTED=true
            FORMAT_TOOL="prettier"
        fi
        ;;

    yaml|yml)
        # YAML - 使用 prettier
        if command -v prettier &> /dev/null; then
            prettier --write "$FILE_PATH" &> /dev/null 2>&1
            FORMATTED=true
            FORMAT_TOOL="prettier"
        fi
        ;;
esac

# 輸出格式化結果
if [ "$FORMATTED" = true ]; then
    echo "✨ 自動格式化: $FILENAME ($FORMAT_TOOL)"
fi

# 額外檢查：偵測潛在問題
WARNINGS=""

# 檢查硬編碼的敏感資訊模式
case "$EXTENSION" in
    js|jsx|ts|tsx|py|go|rs|java|rb)
        # 檢查可能的硬編碼 API key 或密碼
        if grep -qiE "(api[_-]?key|password|secret|token)[[:space:]]*[:=][[:space:]]*['\"][^'\"]+['\"]" "$FILE_PATH" 2>/dev/null; then
            WARNINGS="${WARNINGS}⚠️ 偵測到可能的硬編碼敏感資訊\n"
        fi

        # 檢查 localhost 或 127.0.0.1 硬編碼
        if grep -qE "(localhost|127\.0\.0\.1|0\.0\.0\.0):[0-9]+" "$FILE_PATH" 2>/dev/null; then
            WARNINGS="${WARNINGS}💡 偵測到硬編碼的本地位址（考慮使用環境變數）\n"
        fi
        ;;
esac

# 檢查 TODO/FIXME 標記
TODO_COUNT=$(grep -ciE "TODO|FIXME|XXX|HACK" "$FILE_PATH" 2>/dev/null | head -1 | tr -d '\n\r ' || echo "0")
if [ "$TODO_COUNT" -gt 0 ]; then
    WARNINGS="${WARNINGS}📝 檔案中有 $TODO_COUNT 個 TODO/FIXME 標記\n"
fi

# 輸出警告
if [ -n "$WARNINGS" ]; then
    echo ""
    echo "┌─ 程式碼檢查 ────────────────────────────┐"
    echo -e "$WARNINGS" | sed 's/^/│ /'
    echo "└──────────────────────────────────────────┘"
fi

exit 0
