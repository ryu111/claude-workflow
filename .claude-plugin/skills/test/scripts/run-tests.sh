#!/bin/bash
# run-tests.sh - 統一的測試執行腳本
# 用法: ./run-tests.sh [all|regression|specific] [pattern]

MODE="${1:-all}"
PATTERN="${2:-}"

# 偵測框架
detect_framework() {
    if [ -f "package.json" ]; then
        if grep -q '"vitest"' package.json 2>/dev/null; then
            echo "vitest"
        elif grep -q '"jest"' package.json 2>/dev/null; then
            echo "jest"
        else
            echo "npm"
        fi
    elif [ -f "pyproject.toml" ] || [ -f "pytest.ini" ] || [ -d "tests" ]; then
        echo "pytest"
    elif [ -f "go.mod" ]; then
        echo "go"
    elif [ -f "Cargo.toml" ]; then
        echo "cargo"
    else
        echo "unknown"
    fi
}

FRAMEWORK=$(detect_framework)
echo "🧪 Test Framework: $FRAMEWORK"
echo "📋 Mode: $MODE"
echo "---"

run_tests() {
    case "$FRAMEWORK" in
        jest|vitest|npm)
            case "$MODE" in
                all)
                    npm test
                    ;;
                regression)
                    npm test -- --testPathPattern=".*"
                    ;;
                specific)
                    npm test -- --testPathPattern="$PATTERN"
                    ;;
            esac
            ;;
        pytest)
            case "$MODE" in
                all)
                    pytest -v
                    ;;
                regression)
                    pytest -v --tb=short
                    ;;
                specific)
                    pytest -v "$PATTERN"
                    ;;
            esac
            ;;
        go)
            case "$MODE" in
                all)
                    go test -v ./...
                    ;;
                regression)
                    go test ./...
                    ;;
                specific)
                    go test -v "./$PATTERN/..."
                    ;;
            esac
            ;;
        cargo)
            case "$MODE" in
                all)
                    cargo test
                    ;;
                regression)
                    cargo test --lib
                    ;;
                specific)
                    cargo test "$PATTERN"
                    ;;
            esac
            ;;
        *)
            echo "❌ Unknown test framework"
            exit 1
            ;;
    esac
}

# 執行測試並捕獲結果
run_tests
EXIT_CODE=$?

echo "---"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Tests PASSED"
else
    echo "❌ Tests FAILED (exit code: $EXIT_CODE)"
fi

exit $EXIT_CODE
