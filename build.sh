#!/bin/bash
#
# DeepSeekMonitor - 构建脚本
#
# 用法:
#   ./build.sh           # Release 构建
#   ./build.sh debug     # Debug 构建
#   ./build.sh run       # 构建并运行
#   ./build.sh clean     # 清理构建产物
#

set -e

PROJECT_NAME="DeepSeekMonitor"
BUILD_DIR=".build"
WIDGET_NAME="WidgetSupport"
WIDGET_APPEX="WidgetSupport.appex"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

increment_build() {
    local plist="Resources/Info.plist"
    local widget_plist="Sources/WidgetSupport/Info.plist"
    local current=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$plist" 2>/dev/null || echo "1")
    local next=$((current + 1))
    /usr/libexec/PlistBuddy -c "Set CFBundleVersion $next" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set CFBundleVersion $next" "$widget_plist" 2>/dev/null || true
    info "Build 版本号: $next"
}

kill_running_app() {
    OLD_PID=$(pgrep -x "${PROJECT_NAME}" 2>/dev/null || true)
    if [ -n "$OLD_PID" ]; then
        info "发现旧进程 (PID: $OLD_PID)，正在关闭..."
        kill "$OLD_PID" 2>/dev/null || true
        sleep 1
        if kill -0 "$OLD_PID" 2>/dev/null; then
            kill -9 "$OLD_PID" 2>/dev/null || true
        fi
        info "旧进程已关闭"
    fi
}

copy_app_resources() {
    APP_BUNDLE="$1"

    cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/"

    if [ -f "Resources/deepseek-color.svg" ]; then
        cp "Resources/deepseek-color.svg" "${APP_BUNDLE}/Contents/Resources/"
    fi
    if [ -f "Resources/deepseek-color.png" ]; then
        cp "Resources/deepseek-color.png" "${APP_BUNDLE}/Contents/Resources/"
    fi
    if [ -f "Resources/deepseek-menu.png" ]; then
        cp "Resources/deepseek-menu.png" "${APP_BUNDLE}/Contents/Resources/"
    fi

    if [ -f "Resources/AppIcon.icns" ]; then
        cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
        info "已添加 App 图标"
    else
        warn "未找到 Resources/AppIcon.icns，使用默认图标"
        warn "运行 ./build.sh icon 从 SVG 生成图标"
    fi
}

embed_widget_extension() {
    APP_BUNDLE="$1"
    WIDGET_BINARY="$2"
    APPEX_DIR="${APP_BUNDLE}/Contents/PlugIns/${WIDGET_APPEX}"

    mkdir -p "${APPEX_DIR}/Contents/MacOS"

    cp "$WIDGET_BINARY" "${APPEX_DIR}/Contents/MacOS/${WIDGET_NAME}"
    chmod +x "${APPEX_DIR}/Contents/MacOS/${WIDGET_NAME}"

    if [ -f "Sources/WidgetSupport/Info.plist" ]; then
        cp "Sources/WidgetSupport/Info.plist" "${APPEX_DIR}/Contents/"
    fi

    info "已嵌入 Widget Extension: ${WIDGET_APPEX}"
}

sign_bundle() {
    APP_BUNDLE="$1"
    ENTITLEMENTS="DeepSeekMonitor.entitlements"

    if [ ! -f "$ENTITLEMENTS" ]; then
        warn "未找到 Entitlements 文件 ($ENTITLEMENTS)，跳过签名"
        return
    fi

    APPEX_DIR="${APP_BUNDLE}/Contents/PlugIns/${WIDGET_APPEX}"

    if [ -d "$APPEX_DIR" ]; then
        info "签名 Widget Extension..."
        codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APPEX_DIR" 2>/dev/null || \
            warn "Widget Extension 签名失败（非致命）"
    fi

    info "签名主 App..."
    codesign --force --sign - --entitlements "$ENTITLEMENTS" \
        "${APP_BUNDLE}/Contents/MacOS/${PROJECT_NAME}" 2>/dev/null || \
        warn "主 App 签名失败（非致命）"

    info "签名完成（ad-hoc）"
}

create_app_bundle() {
    BINARY_PATH="$1"
    APP_BUNDLE="${PROJECT_NAME}.app"

    rm -rf "$APP_BUNDLE"
    mkdir -p "${APP_BUNDLE}/Contents/MacOS"
    mkdir -p "${APP_BUNDLE}/Contents/Resources"

    cp "$BINARY_PATH" "${APP_BUNDLE}/Contents/MacOS/${PROJECT_NAME}"
    chmod +x "${APP_BUNDLE}/Contents/MacOS/${PROJECT_NAME}"
    copy_app_resources "$APP_BUNDLE"
}

build_release_universal() {
    ARM_TRIPLE="arm64-apple-macosx14.0"
    INTEL_TRIPLE="x86_64-apple-macosx14.0"
    UNIVERSAL_DIR="${BUILD_DIR}/universal/release"
    UNIVERSAL_BIN="${UNIVERSAL_DIR}/${PROJECT_NAME}"

    info "编译 Apple Silicon 架构 (${ARM_TRIPLE})..."
    swift build -c release --triple "$ARM_TRIPLE"
    ARM_BIN_DIR=$(swift build -c release --triple "$ARM_TRIPLE" --show-bin-path)
    ARM_BIN="${ARM_BIN_DIR}/${PROJECT_NAME}"

    info "编译 Intel 架构 (${INTEL_TRIPLE})..."
    swift build -c release --triple "$INTEL_TRIPLE"
    INTEL_BIN_DIR=$(swift build -c release --triple "$INTEL_TRIPLE" --show-bin-path)
    INTEL_BIN="${INTEL_BIN_DIR}/${PROJECT_NAME}"

    mkdir -p "$UNIVERSAL_DIR"
    info "合并 Universal Binary..."
    lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$UNIVERSAL_BIN"
    chmod +x "$UNIVERSAL_BIN"
    lipo -info "$UNIVERSAL_BIN"

    # Widget Extension
    info "编译 Widget Extension (${ARM_TRIPLE})..."
    swift build -c release --target "${WIDGET_NAME}" --triple "$ARM_TRIPLE" 2>/dev/null || true
    ARM_WIDGET_DIR=$(swift build -c release --target "${WIDGET_NAME}" --triple "$ARM_TRIPLE" --show-bin-path 2>/dev/null || echo "")
    ARM_WIDGET="${ARM_WIDGET_DIR}/${WIDGET_NAME}"

    info "编译 Widget Extension (${INTEL_TRIPLE})..."
    swift build -c release --target "${WIDGET_NAME}" --triple "$INTEL_TRIPLE" 2>/dev/null || true
    INTEL_WIDGET_DIR=$(swift build -c release --target "${WIDGET_NAME}" --triple "$INTEL_TRIPLE" --show-bin-path 2>/dev/null || echo "")
    INTEL_WIDGET="${INTEL_WIDGET_DIR}/${WIDGET_NAME}"

    WIDGET_UNIVERSAL="${UNIVERSAL_DIR}/${WIDGET_NAME}"
    if [ -n "$ARM_WIDGET" ] && [ -f "$ARM_WIDGET" ] && [ -n "$INTEL_WIDGET" ] && [ -f "$INTEL_WIDGET" ]; then
        info "合并 Widget Universal Binary..."
        lipo -create "$ARM_WIDGET" "$INTEL_WIDGET" -output "$WIDGET_UNIVERSAL" 2>/dev/null || true
        chmod +x "$WIDGET_UNIVERSAL" 2>/dev/null || true
    else
        warn "Widget Extension 编译不完整，尝试单一架构..."
        if [ -f "$ARM_WIDGET" ]; then
            cp "$ARM_WIDGET" "${UNIVERSAL_DIR}/${WIDGET_NAME}"
        fi
    fi

    create_app_bundle "$UNIVERSAL_BIN"

    if [ -f "${UNIVERSAL_DIR}/${WIDGET_NAME}" ]; then
        embed_widget_extension "${PROJECT_NAME}.app" "${UNIVERSAL_DIR}/${WIDGET_NAME}"
    fi
    sign_bundle "${PROJECT_NAME}.app"
}

# 检测 Xcode 命令行工具
if ! command -v swift &> /dev/null; then
    error "未找到 Swift 编译器。请安装 Xcode 或 Xcode Command Line Tools。"
    exit 1
fi

# 检测 macOS
if [[ "$(uname)" != "Darwin" ]]; then
    error "此脚本仅支持 macOS。"
    exit 1
fi

MODE="${1:-release}"

case "$MODE" in
    debug)
        increment_build
        info "Debug 构建..."
        swift build -c debug
        swift build -c debug --target "${WIDGET_NAME}" 2>/dev/null || true
        info "Debug 构建完成！可执行文件: ${BUILD_DIR}/debug/${PROJECT_NAME}"
        ;;

    release)
        info "Release Universal 构建..."
        increment_build

        kill_running_app
        build_release_universal

        info "Release 构建完成！"
        info "App Bundle: ${PROJECT_NAME}.app"
        info "运行: open ${PROJECT_NAME}.app"
        ;;

    run)
        info "构建并运行..."
        increment_build

        swift build -c debug
        swift build -c debug --target "${WIDGET_NAME}" 2>/dev/null || true
        APP_PATH="${BUILD_DIR}/debug/${PROJECT_NAME}"

        info "启动 ${PROJECT_NAME}..."
        "${APP_PATH}" &
        ;;

    icon)
        info "从 SVG 生成 App 图标..."
        SVG_FILE="Resources/deepseek-color.svg"
        ICNS_FILE="Resources/AppIcon.icns"
        ICONSET="AppIcon.iconset"

        if [ ! -f "$SVG_FILE" ]; then
            error "未找到 SVG 文件: $SVG_FILE"
            exit 1
        fi

        if ! command -v rsvg-convert &> /dev/null; then
            warn "未安装 rsvg-convert，尝试用 Homebrew 安装..."
            brew install librsvg 2>/dev/null || {
                error "安装失败。请手动安装: brew install librsvg"
                error "或手动将 SVG 转换为 PNG/ICNS"
                exit 1
            }
        fi

        rm -rf "$ICONSET"
        mkdir -p "$ICONSET"

        for size in 16 32 64 128 256 512 1024; do
            rsvg-convert "$SVG_FILE" -w $size -h $size \
                -o "${ICONSET}/icon_${size}x${size}.png"
            if [ $size -le 512 ]; then
                half=$((size / 2))
                if [ $half -ge 16 ]; then
                    cp "${ICONSET}/icon_${size}x${size}.png" \
                       "${ICONSET}/icon_${half}x${half}@2x.png"
                fi
            fi
        done

        iconutil -c icns "$ICONSET" -o "$ICNS_FILE"
        rm -rf "$ICONSET"

        if [ -f "$ICNS_FILE" ]; then
            info "图标生成完成: $ICNS_FILE"
        else
            error "图标生成失败"
            exit 1
        fi
        ;;

    restart)
        "$0" release
        open "${PROJECT_NAME}.app"
        info "已启动 ${PROJECT_NAME}.app"
        ;;

    dmg)
        info "生成 DMG 安装包..."
        "$0" release

        APP_BUNDLE="${PROJECT_NAME}.app"
        DMG_NAME="${PROJECT_NAME}-v1.3.1"
        DMG_TEMP="${DMG_NAME}-temp.dmg"
        DMG_FINAL="${DMG_NAME}.dmg"
        STAGING="dmg-staging"

        rm -f "$DMG_TEMP" "$DMG_FINAL"
        rm -rf "$STAGING"
        mkdir -p "$STAGING"
        cp -R "$APP_BUNDLE" "$STAGING/"
        ln -s /Applications "$STAGING/Applications"

        hdiutil create \
            -volname "DeepSeek Monitor" \
            -srcfolder "$STAGING" \
            -ov \
            -format UDZO \
            -size 64m \
            "$DMG_TEMP"

        hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL"
        rm -f "$DMG_TEMP"
        rm -rf "$STAGING"

        info "DMG 构建完成: ${DMG_FINAL}"
        info "直接打开 DMG 拖入 Applications 即可安装"
        ;;

    *)
        echo "用法: $0 {debug|release|run|clean|icon|restart|dmg}"
        exit 1
        ;;
esac
