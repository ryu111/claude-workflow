#!/bin/bash
# init.sh - 零配置部署腳本
# 功能: 自動偵測專案類型，初始化 .claude/steering/ 配置
# 用法: bash init.sh [--force]

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Plugin 根目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="${PLUGIN_ROOT}/templates/steering"

# 目標目錄
TARGET_DIR="${PWD}/.claude/steering"

# 參數解析
FORCE=false
if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
    FORCE=true
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              🚀 Claude Workflow 初始化                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# 檢查是否已初始化
if [ -d "$TARGET_DIR" ] && [ "$FORCE" = false ]; then
    echo -e "${YELLOW}⚠️  已偵測到 .claude/steering/ 目錄${NC}"
    echo ""
    echo "   現有檔案："
    ls -la "$TARGET_DIR" 2>/dev/null | grep -v "^total" | grep -v "^d" | awk '{print "   - " $NF}' || true
    echo ""
    echo "   使用 --force 參數覆蓋現有配置"
    echo "   例如: bash init.sh --force"
    echo ""
    exit 0
fi

# 偵測專案類型
detect_project_type() {
    local project_type="generic"
    local tech_stack=""

    # Node.js / JavaScript / TypeScript
    if [ -f "package.json" ]; then
        project_type="node"

        # 檢查框架
        if grep -q "next" package.json 2>/dev/null; then
            tech_stack="Next.js"
        elif grep -q "react" package.json 2>/dev/null; then
            tech_stack="React"
        elif grep -q "vue" package.json 2>/dev/null; then
            tech_stack="Vue"
        elif grep -q "svelte" package.json 2>/dev/null; then
            tech_stack="Svelte"
        elif grep -q "express" package.json 2>/dev/null; then
            tech_stack="Express"
        elif grep -q "fastify" package.json 2>/dev/null; then
            tech_stack="Fastify"
        fi

        # TypeScript?
        if [ -f "tsconfig.json" ]; then
            project_type="typescript"
        fi
    fi

    # Python
    if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
        project_type="python"

        if [ -f "pyproject.toml" ]; then
            if grep -q "fastapi" pyproject.toml 2>/dev/null; then
                tech_stack="FastAPI"
            elif grep -q "django" pyproject.toml 2>/dev/null; then
                tech_stack="Django"
            elif grep -q "flask" pyproject.toml 2>/dev/null; then
                tech_stack="Flask"
            fi
        fi
    fi

    # Go
    if [ -f "go.mod" ]; then
        project_type="go"

        if grep -q "gin-gonic" go.mod 2>/dev/null; then
            tech_stack="Gin"
        elif grep -q "echo" go.mod 2>/dev/null; then
            tech_stack="Echo"
        elif grep -q "fiber" go.mod 2>/dev/null; then
            tech_stack="Fiber"
        fi
    fi

    # Rust
    if [ -f "Cargo.toml" ]; then
        project_type="rust"

        if grep -q "actix" Cargo.toml 2>/dev/null; then
            tech_stack="Actix"
        elif grep -q "axum" Cargo.toml 2>/dev/null; then
            tech_stack="Axum"
        fi
    fi

    echo "$project_type|$tech_stack"
}

# 偵測專案類型
echo "🔍 偵測專案類型..."
DETECTION=$(detect_project_type)
PROJECT_TYPE=$(echo "$DETECTION" | cut -d'|' -f1)
TECH_STACK=$(echo "$DETECTION" | cut -d'|' -f2)

echo ""
echo -e "   專案類型: ${GREEN}${PROJECT_TYPE}${NC}"
if [ -n "$TECH_STACK" ]; then
    echo -e "   技術框架: ${GREEN}${TECH_STACK}${NC}"
fi
echo ""

# 建立目錄
echo "📁 建立 .claude/steering/ 目錄..."
mkdir -p "$TARGET_DIR"

# 複製模板
echo "📋 複製 Steering 模板..."

# 複製 workflow.md
if [ -f "${TEMPLATES_DIR}/workflow.md" ]; then
    cp "${TEMPLATES_DIR}/workflow.md" "${TARGET_DIR}/workflow.md"
    echo -e "   ${GREEN}✓${NC} workflow.md"
else
    echo -e "   ${YELLOW}⚠${NC} workflow.md 模板不存在"
fi

# 複製 tech.md 並填入偵測到的技術
if [ -f "${TEMPLATES_DIR}/tech.md" ]; then
    cp "${TEMPLATES_DIR}/tech.md" "${TARGET_DIR}/tech.md"

    # 自動填入偵測到的資訊
    case "$PROJECT_TYPE" in
        typescript)
            sed -i.bak 's/<!-- TypeScript \/ Python \/ Go -->/TypeScript/' "${TARGET_DIR}/tech.md" 2>/dev/null || true
            sed -i.bak 's/<!-- Node.js \/ Python \/ Go -->/Node.js/' "${TARGET_DIR}/tech.md" 2>/dev/null || true
            ;;
        node)
            sed -i.bak 's/<!-- TypeScript \/ Python \/ Go -->/JavaScript/' "${TARGET_DIR}/tech.md" 2>/dev/null || true
            sed -i.bak 's/<!-- Node.js \/ Python \/ Go -->/Node.js/' "${TARGET_DIR}/tech.md" 2>/dev/null || true
            ;;
        python)
            sed -i.bak 's/<!-- TypeScript \/ Python \/ Go -->/Python/' "${TARGET_DIR}/tech.md" 2>/dev/null || true
            sed -i.bak 's/<!-- Node.js \/ Python \/ Go -->/Python/' "${TARGET_DIR}/tech.md" 2>/dev/null || true
            ;;
        go)
            sed -i.bak 's/<!-- TypeScript \/ Python \/ Go -->/Go/' "${TARGET_DIR}/tech.md" 2>/dev/null || true
            sed -i.bak 's/<!-- Node.js \/ Python \/ Go -->/Go/' "${TARGET_DIR}/tech.md" 2>/dev/null || true
            ;;
        rust)
            sed -i.bak 's/<!-- TypeScript \/ Python \/ Go -->/Rust/' "${TARGET_DIR}/tech.md" 2>/dev/null || true
            sed -i.bak 's/<!-- Node.js \/ Python \/ Go -->/Rust/' "${TARGET_DIR}/tech.md" 2>/dev/null || true
            ;;
    esac

    # 填入框架
    if [ -n "$TECH_STACK" ]; then
        sed -i.bak "s/<!-- Next.js \/ FastAPI \/ Gin -->/$TECH_STACK/" "${TARGET_DIR}/tech.md" 2>/dev/null || true
    fi

    # 清理備份檔案
    rm -f "${TARGET_DIR}/tech.md.bak"

    echo -e "   ${GREEN}✓${NC} tech.md (已填入偵測資訊)"
else
    echo -e "   ${YELLOW}⚠${NC} tech.md 模板不存在"
fi

# 複製 structure.md
if [ -f "${TEMPLATES_DIR}/structure.md" ]; then
    cp "${TEMPLATES_DIR}/structure.md" "${TARGET_DIR}/structure.md"
    echo -e "   ${GREEN}✓${NC} structure.md"
else
    echo -e "   ${YELLOW}⚠${NC} structure.md 模板不存在"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              ✅ 初始化完成                                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "已建立的檔案："
echo ""
ls -la "$TARGET_DIR" 2>/dev/null | grep -v "^total" | grep -v "^d" | awk '{print "   " $NF}' || true
echo ""
echo "📝 下一步："
echo "   1. 編輯 .claude/steering/tech.md 填入完整技術棧"
echo "   2. 編輯 .claude/steering/structure.md 說明專案結構"
echo "   3. 開始使用 D→R→T 工作流"
echo ""
