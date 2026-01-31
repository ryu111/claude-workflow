#!/bin/bash
# test-ts-027.sh - Debugger Agent 驗證
# 驗證: agents/debugger.md 存在、frontmatter 完整、skills 引用有效、包含特定內容

echo "=== TS-027: Debugger Agent 驗證 ==="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AGENT_FILE="$PROJECT_ROOT/agents/debugger.md"
SKILLS_DIR="$PROJECT_ROOT/skills"

# 驗證結果
PASS=true

# 1. 檢查檔案存在
echo "1. 檢查檔案存在..."
if [ ! -f "$AGENT_FILE" ]; then
    echo "   ❌ agents/debugger.md 不存在"
    PASS=false
    exit 1
else
    echo "   ✅ agents/debugger.md 存在"
fi

# 2. 檢查 frontmatter 必要欄位
echo ""
echo "2. 檢查 frontmatter 必要欄位..."
required_fields=("name" "description" "skills" "tools")
all_fields_present=true

for field in "${required_fields[@]}"; do
    if ! grep -q "^${field}:" "$AGENT_FILE"; then
        echo "   ❌ 缺少必要欄位: $field"
        PASS=false
        all_fields_present=false
    fi
done

if [ "$all_fields_present" = true ]; then
    echo "   ✅ 所有必要欄位存在 (name, description, skills, tools)"
fi

# 3. 驗證 skills 引用存在
echo ""
echo "3. 驗證 skills 引用..."
skills_line=$(grep "^skills:" "$AGENT_FILE" 2>/dev/null | head -1)
if [ -z "$skills_line" ]; then
    echo "   ❌ 無法讀取 skills 欄位"
    PASS=false
else
    skills_value=$(echo "$skills_line" | sed 's/^skills: *//')
    IFS=',' read -ra skill_arr <<< "$skills_value"

    skills_valid=true
    skill_count=0
    for skill in "${skill_arr[@]}"; do
        skill=$(echo "$skill" | xargs)
        [ -z "$skill" ] && continue

        skill_count=$((skill_count + 1))

        skill_dir="$SKILLS_DIR/$skill"
        if [ ! -d "$skill_dir" ]; then
            echo "   ❌ 引用不存在的 skill: $skill"
            PASS=false
            skills_valid=false
        elif [ ! -f "$skill_dir/SKILL.md" ]; then
            echo "   ❌ skill '$skill' 缺少 SKILL.md"
            PASS=false
            skills_valid=false
        fi
    done

    if [ "$skills_valid" = true ]; then
        echo "   ✅ 所有 skills 引用有效 ($skill_count skills)"
    fi
fi

# 4. 檢查特定內容
echo ""
echo "4. 檢查特定內容..."
content_checks=true

# 檢查除錯相關內容
if ! grep -q "除錯\|debug" "$AGENT_FILE"; then
    echo "   ❌ 缺少除錯相關內容"
    PASS=false
    content_checks=false
fi

# 檢查錯誤分析內容
if ! grep -q "錯誤\|error\|失敗\|分析" "$AGENT_FILE"; then
    echo "   ❌ 缺少錯誤分析相關內容"
    PASS=false
    content_checks=false
fi

# 檢查根因分析內容
if ! grep -q "根因\|root cause\|5 Whys" "$AGENT_FILE"; then
    echo "   ❌ 缺少根因分析方法"
    PASS=false
    content_checks=false
fi

# 檢查修復方案內容
if ! grep -q "修復\|fix\|repair" "$AGENT_FILE"; then
    echo "   ❌ 缺少修復方案相關內容"
    PASS=false
    content_checks=false
fi

# 檢查 TESTER 互動內容
if ! grep -q "TESTER" "$AGENT_FILE"; then
    echo "   ❌ 缺少與 TESTER 的流程說明"
    PASS=false
    content_checks=false
fi

if [ "$content_checks" = true ]; then
    echo "   ✅ 包含必要內容 (除錯、錯誤分析、根因、修復、TESTER 互動)"
fi

# 5. 檢查強制行為格式
echo ""
echo "5. 檢查強制輸出格式..."
format_checks=true

if ! grep -q "⚡.*DEBUGGER.*開始分析" "$AGENT_FILE"; then
    echo "   ❌ 缺少啟動時輸出格式"
    PASS=false
    format_checks=false
fi

if ! grep -q "✅.*DEBUGGER.*完成分析" "$AGENT_FILE"; then
    echo "   ❌ 缺少結束時輸出格式"
    PASS=false
    format_checks=false
fi

if [ "$format_checks" = true ]; then
    echo "   ✅ 強制輸出格式完整"
fi

# 結果
echo ""
if [ "$PASS" = true ]; then
    echo "✅ TS-027 PASS: Debugger Agent 驗證通過"
    exit 0
else
    echo "❌ TS-027 FAIL"
    exit 1
fi
