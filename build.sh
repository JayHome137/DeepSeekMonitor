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

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

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
        info "Debug 构建..."
        swift build -c debug
        info "Debug 构建完成！可执行文件: ${BUILD_DIR}/debug/${PROJECT_NAME}"
        ;;

    release)
        info "Release 构建..."

        # 0. 先杀掉正在运行的旧版本
        OLD_PID=$(pgrep -x "${PROJECT_NAME}" 2>/dev/null || true)
        if [ -n "$OLD_PID" ]; then
            info "发现旧进程 (PID: $OLD_PID)，正在关闭..."
            kill "$OLD_PID" 2>/dev/null || true
            sleep 1
            # 如果没退出，强制杀
            if kill -0 "$OLD_PID" 2>/dev/null; then
                kill -9 "$OLD_PID" 2>/dev/null || true
            fi
            info "旧进程已关闭"
        fi

        # 1. 编译
        swift build -c release

        # 2. 创建 .app 包结构
        APP_BUNDLE="${PROJECT_NAME}.app"
        rm -rf "$APP_BUNDLE"
        mkdir -p "${APP_BUNDLE}/Contents/MacOS"
        mkdir -p "${APP_BUNDLE}/Contents/Resources"

        # 3. 复制可执行文件
        cp "${BUILD_DIR}/release/${PROJECT_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

        # 4. 复制 Info.plist
        cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/"

        # 5. 资源文件
        # 菜单栏图标 SVG
        if [ -f "Resources/deepseek-color.svg" ]; then
            cp "Resources/deepseek-color.svg" "${APP_BUNDLE}/Contents/Resources/"
        fi
        if [ -f "Resources/deepseek-color.png" ]; then
            cp "Resources/deepseek-color.png" "${APP_BUNDLE}/Contents/Resources/"
        fi
        if [ -f "Resources/deepseek-menu.png" ]; then
            cp "Resources/deepseek-menu.png" "${APP_BUNDLE}/Contents/Resources/"
        fi

        # App 图标（如果存在）
        if [ -f "Resources/AppIcon.icns" ]; then
            cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
            info "已添加 App 图标"
        else
            warn "未找到 Resources/AppIcon.icns，使用默认图标"
            warn "运行 ./build.sh icon 从 SVG 生成图标"
        fi

        info "Release 构建完成！"
        info "App Bundle: ${APP_BUNDLE}"
        info "运行: open ${APP_BUNDLE}"
        ;;

    run)
        info "构建并运行..."

        swift build -c debug
        APP_PATH="${BUILD_DIR}/debug/${PROJECT_NAME}"

        # Debug 模式下直接运行二进制文件
        # （注意：因为没有 Info.plist 会显示 Dock 图标，用于调试）
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

        # 检查 rsvg-convert (librsvg)
        if ! command -v rsvg-convert &> /dev/null; then
            warn "未安装 rsvg-convert，尝试用 Homebrew 安装..."
            brew install librsvg 2>/dev/null || {
                error "安装失败。请手动安装: brew install librsvg"
                error "或手动将 SVG 转换为 PNG/ICNS"
                exit 1
            }
        fi

        # 创建 iconset 目录
        rm -rf "$ICONSET"
        mkdir -p "$ICONSET"

        # 生成各种尺寸的 PNG
        for size in 16 32 64 128 256 512 1024; do
            rsvg-convert "$SVG_FILE" -w $size -h $size \
                -o "${ICONSET}/icon_${size}x${size}.png"

            # 如果尺寸需要 @2x
            if [ $size -le 512 ]; then
                half=$((size / 2))
                if [ $half -ge 16 ]; then
                    cp "${ICONSET}/icon_${size}x${size}.png" \
                       "${ICONSET}/icon_${half}x${half}@2x.png"
                fi
            fi
        done

        # 用 iconutil 生成 .icns
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
        # 构建 + 自动重启
        "$0" release
        open "${PROJECT_NAME}.app"
        info "已启动 ${PROJECT_NAME}.app"
        ;;

    dmg)
        # 构建 + 生成 DMG 安装包
        info "生成 DMG 安装包..."

        "$0" release

        APP_BUNDLE="${PROJECT_NAME}.app"
        DMG_NAME="${PROJECT_NAME}-v1.1.0"
        DMG_TEMP="${DMG_NAME}-temp.dmg"
        DMG_FINAL="${DMG_NAME}.dmg"
        STAGING="dmg-staging"

        # 创建 DMG 模板目录
        rm -f "$DMG_TEMP" "$DMG_FINAL"
        rm -rf "$STAGING"
        mkdir -p "$STAGING"
        cp -R "$APP_BUNDLE" "$STAGING/"
        # 创建 Applications 快捷方式
        ln -s /Applications "$STAGING/Applications"

        # 生成 DMG（精简格式）
        hdiutil create \
            -volname "DeepSeek Monitor" \
            -srcfolder "$STAGING" \
            -ov \
            -format UDZO \
            -size 64m \
            "$DMG_TEMP"

        # 转换最终格式
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
