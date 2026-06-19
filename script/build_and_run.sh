#!/usr/bin/env bash
# Omnipo 统一构建与运行入口
#
# 用法:
#   ./script/build_and_run.sh run        # 构建 Debug 并启动应用
#   ./script/build_and_run.sh debug      # 构建 Debug,启动应用并启用日志输出
#   ./script/build_and_run.sh logs       # 使用 log stream 查看 Omnipo 子系统日志
#   ./script/build_and_run.sh telemetry  # 查看 Instruments 友好的诊断输出
#   ./script/build_and_run.sh verify     # 运行单元测试 + Debug 构建
#   ./script/build_and_run.sh build      # 仅构建 Debug
#   ./script/build_and_run.sh test       # 仅运行单元测试
#   ./script/build_and_run.sh stop       # 仅停止在运行的 Omnipo 进程

set -euo pipefail

MODE="${1:-run}"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="$PROJECT_ROOT/Omnipo.xcodeproj"
SCHEME="Omnipo"
CONFIGURATION="Debug"
DERIVED_DATA="$PROJECT_ROOT/build/DerivedData"
APP_BUNDLE_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/Omnipo.app"
APP_EXECUTABLE="$APP_BUNDLE_PATH/Contents/MacOS/Omnipo"
BUNDLE_ID="com.omnipo.app"
LOG_SUBSYSTEM="$BUNDLE_ID"
LOG_BIN="/usr/bin/log"

note() {
    printf '[omnipo] %s\n' "$*"
}

err() {
    printf '[omnipo][error] %s\n' "$*" >&2
}

stop_running() {
    note "停止在运行的 Omnipo 进程"
    pkill -x Omnipo 2>/dev/null || true
    pkill -f "$APP_BUNDLE_PATH" 2>/dev/null || true
}

build_app() {
    note "构建 $CONFIGURATION (DerivedData=$DERIVED_DATA)"
    xcodebuild \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" \
        -destination "platform=macOS" \
        build
}

run_app() {
    if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
        err "未找到构建产物:$APP_BUNDLE_PATH"
        exit 1
    fi
    note "启动 $APP_BUNDLE_PATH"
    open "$APP_BUNDLE_PATH"
}

run_app_debug() {
    if [[ ! -x "$APP_EXECUTABLE" ]]; then
        err "未找到可执行文件:$APP_EXECUTABLE"
        exit 1
    fi
    note "以调试模式启动并附带 stdout/stderr"
    "$APP_EXECUTABLE"
}

stream_logs() {
    note "流式输出 $LOG_SUBSYSTEM 子系统日志(Ctrl+C 退出)"
    "$LOG_BIN" stream --predicate "subsystem == '$LOG_SUBSYSTEM'" --level debug
}

run_telemetry() {
    note "查看 Omnipo telemetry(OSLog compact)"
    "$LOG_BIN" show \
        --predicate "subsystem == '$LOG_SUBSYSTEM'" \
        --last 10m \
        --style compact
}

run_tests() {
    note "运行 OmnipoTests"
    xcodebuild \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" \
        -destination "platform=macOS" \
        test
}

case "$MODE" in
    run)
        stop_running
        build_app
        run_app
        ;;
    debug)
        stop_running
        build_app
        run_app_debug
        ;;
    build)
        build_app
        ;;
    test)
        run_tests
        ;;
    verify)
        build_app
        run_tests
        ;;
    logs)
        stream_logs
        ;;
    telemetry)
        run_telemetry
        ;;
    stop)
        stop_running
        ;;
    *)
        err "未知模式:$MODE"
        echo "可用模式: run | debug | build | test | verify | logs | telemetry | stop"
        exit 2
        ;;
esac
