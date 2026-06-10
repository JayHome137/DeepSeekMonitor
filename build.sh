#!/bin/bash
#
# DeepSeekMonitor - 构建脚本
#
# 用法:
#   ./build.sh           # Release 构建 + DMG
#   ./build.sh debug     # Debug 构建
#   ./build.sh run       # 构建并运行
#   ./build.sh clean     # 清理构建产物
#

set -e

PROJECT_NAME="DeepSeekMonitor"
BUILD_DIR=".build"
WIDGET_NAME="WidgetSupport"
WIDGET_APPEX="WidgetSupport.appex"
APP_BUNDLE_ID="com.deepseek.monitor"
WIDGET_BUNDLE_ID="com.deepseek.monitor.widget"
TEAM_ID="N5YV5FV235"
MARKETING_VERSION="1.4.3"

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
    /usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $MARKETING_VERSION" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $MARKETING_VERSION" "$widget_plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set CFBundleVersion $next" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set CFBundleVersion $next" "$widget_plist" 2>/dev/null || true
    info "内部 Build 版本号: $next"
}

current_build_version() {
    /usr/libexec/PlistBuddy -c "Print CFBundleVersion" "Resources/Info.plist"
}

create_dmg() {
    local app_bundle="${PROJECT_NAME}.app"
    local dmg_name="${PROJECT_NAME}-v${MARKETING_VERSION}"
    local dmg_temp="${dmg_name}-temp.dmg"
    local dmg_final="${dmg_name}.dmg"
    local staging="dmg-staging"

    if [ ! -d "$app_bundle" ]; then
        error "未找到 ${app_bundle}，无法生成 DMG"
        exit 1
    fi

    rm -f "$dmg_temp" "$dmg_final"
    rm -rf "$staging"
    mkdir -p "$staging"
    ditto "$app_bundle" "$staging/$app_bundle"
    ln -s /Applications "$staging/Applications"

    hdiutil create \
        -volname "DeepSeek Monitor" \
        -srcfolder "$staging" \
        -ov \
        -format UDZO \
        -size 64m \
        "$dmg_temp"

    hdiutil convert "$dmg_temp" -format UDZO -imagekey zlib-level=9 -o "$dmg_final"
    rm -f "$dmg_temp"
    rm -rf "$staging"

    info "DMG 构建完成: ${dmg_final}"
}

kill_running_app() {
    local pids=()
    local line pid command

    while read -r pid command; do
        [ -n "$pid" ] || continue
        case "$command" in
            *"/${PROJECT_NAME}.app/Contents/MacOS/${PROJECT_NAME}"*|*"/${PROJECT_NAME}.app/Contents/PlugIns/${WIDGET_APPEX}/Contents/MacOS/${WIDGET_NAME}"*)
                pids+=("$pid")
                ;;
        esac
    done < <(ps -axo pid=,command=)

    if [ "${#pids[@]}" -gt 0 ]; then
        info "发现旧进程 (PID: ${pids[*]})，正在关闭..."
        kill "${pids[@]}" 2>/dev/null || true
        sleep 1
        local alive=()
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                alive+=("$pid")
            fi
        done
        if [ "${#alive[@]}" -gt 0 ]; then
            kill -9 "${alive[@]}" 2>/dev/null || true
        fi
        info "旧进程已关闭"
    fi
}

unregister_app_bundle() {
    local app_bundle="$1"

    if [ ! -d "$app_bundle" ]; then
        return
    fi

    local bundle_id
    bundle_id=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$app_bundle/Contents/Info.plist" 2>/dev/null || true)
    if [ "$bundle_id" != "$APP_BUNDLE_ID" ]; then
        return
    fi

    local appex_dir="$app_bundle/Contents/PlugIns/$WIDGET_APPEX"
    if [ -d "$appex_dir" ]; then
        pluginkit -r "$appex_dir" 2>/dev/null || true
    fi

    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -u "$app_bundle" 2>/dev/null || true
}

remove_app_bundle_if_deepseek() {
    local app_bundle="$1"

    if [ ! -d "$app_bundle" ]; then
        return
    fi

    local bundle_id
    bundle_id=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$app_bundle/Contents/Info.plist" 2>/dev/null || true)
    if [ "$bundle_id" != "$APP_BUNDLE_ID" ]; then
        return
    fi

    info "清理旧 DeepSeekMonitor 副本: $app_bundle"
    unregister_app_bundle "$app_bundle"
    rm -rf "$app_bundle"
}

remove_globbed_app_bundles() {
    local pattern="$1"
    local app_bundle

    while IFS= read -r app_bundle; do
        remove_app_bundle_if_deepseek "$app_bundle"
    done < <(compgen -G "$pattern" || true)
}

clear_widgetkit_cache() {
    local chrono_dir="$HOME/Library/Containers/$WIDGET_BUNDLE_ID/Data/SystemData/com.apple.chrono"
    if [ -d "$chrono_dir" ]; then
        rm -rf "$chrono_dir"
        info "已清理 WidgetKit Chrono 缓存: $chrono_dir"
    fi

    local relevance_dir="$HOME/Library/Caches/com.apple.chrono/widget-relevance-cache"
    if [ -d "$relevance_dir" ]; then
        local cache_file
        while IFS= read -r -d '' cache_file; do
            if LC_ALL=C grep -Fqa "$APP_BUNDLE_ID" "$cache_file" 2>/dev/null || \
               LC_ALL=C grep -Fqa "$WIDGET_BUNDLE_ID" "$cache_file" 2>/dev/null; then
                rm -f "$cache_file"
            fi
        done < <(find "$relevance_dir" -type f -print0 2>/dev/null)
        info "已清理 DeepSeekMonitor Widget relevance 缓存"
    fi

    killall chronod 2>/dev/null || true
}

cleanup_project_system_state() {
    info "清理 DeepSeekMonitor 旧注册与 WidgetKit 缓存..."

    remove_app_bundle_if_deepseek "/Applications/${PROJECT_NAME}.app"
    remove_app_bundle_if_deepseek "$HOME/Desktop/${PROJECT_NAME}.app"
    remove_app_bundle_if_deepseek "$HOME/.Trash/${PROJECT_NAME}.app"
    remove_globbed_app_bundles "$HOME/Library/Developer/Xcode/DerivedData/${PROJECT_NAME}-*/Build/Products/Debug/${PROJECT_NAME}.app"

    remove_app_bundle_if_deepseek "${BUILD_DIR}/xcode-release/Release/${PROJECT_NAME}.app"
    rm -rf "${BUILD_DIR}/XcodeWidgetProbe" "${BUILD_DIR}/XcodeReleaseCheck"
    clear_widgetkit_cache
}

copy_app_resources() {
    APP_BUNDLE="$1"

    cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/"
    copy_runtime_resources "$APP_BUNDLE"
}

copy_runtime_resources() {
    APP_BUNDLE="$1"

    mkdir -p "${APP_BUNDLE}/Contents/Resources"

    if [ -f "Resources/deepseek-color.svg" ]; then
        cp "Resources/deepseek-color.svg" "${APP_BUNDLE}/Contents/Resources/"
    fi
    if [ -f "Resources/deepseek-color.png" ]; then
        cp "Resources/deepseek-color.png" "${APP_BUNDLE}/Contents/Resources/"
    fi
    if [ -f "Resources/deepseek-menu.png" ]; then
        cp "Resources/deepseek-menu.png" "${APP_BUNDLE}/Contents/Resources/"
    fi

    compile_asset_catalog "$APP_BUNDLE" "app"
    copy_bundle_icon "$APP_BUNDLE" "App"
}

copy_bundle_icon() {
    APP_BUNDLE="$1"
    LABEL="$2"

    if [ -f "Resources/AppIcon.icns" ]; then
        cp "Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/"
        info "已添加 ${LABEL} 图标"
    else
        warn "未找到 Resources/AppIcon.icns，${LABEL} 将使用默认图标"
        warn "运行 ./build.sh icon 从 SVG 生成图标"
    fi
}

compile_asset_catalog() {
    APP_BUNDLE="$1"
    LABEL="$2"
    ASSETS_DIR="Resources/Assets.xcassets"

    if [ ! -d "$ASSETS_DIR" ]; then
        return
    fi

    mkdir -p "${APP_BUNDLE}/Contents/Resources" "${BUILD_DIR}/assetcatalog"
    PARTIAL_INFO="${BUILD_DIR}/assetcatalog/${LABEL}-asset-info.plist"

    if xcrun actool "$ASSETS_DIR" \
        --compile "${APP_BUNDLE}/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --target-device mac \
        --app-icon AppIcon \
        --output-partial-info-plist "$PARTIAL_INFO" >/tmp/deepseek-actool-${LABEL}.log 2>&1; then
        info "已编译 ${LABEL} Asset Catalog"
    else
        warn "${LABEL} Asset Catalog 编译失败，继续使用已复制的 PNG/ICNS 资源"
        cat /tmp/deepseek-actool-${LABEL}.log 2>/dev/null || true
    fi
}

copy_widget_resources() {
    APPEX_DIR="$1"

    mkdir -p "${APPEX_DIR}/Contents/Resources"

    if [ -f "Resources/deepseek-color.png" ]; then
        cp "Resources/deepseek-color.png" "${APPEX_DIR}/Contents/Resources/"
    fi

    compile_asset_catalog "$APPEX_DIR" "widget"
    copy_bundle_icon "$APPEX_DIR" "Widget"
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

    CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
    if [ -z "$CODE_SIGN_IDENTITY" ]; then
        CODE_SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development|Mac Developer|Developer ID Application/ { print $2; exit }')
    fi

    SIGN_ARGS=(--force --timestamp=none --entitlements "$ENTITLEMENTS")
    if [ -n "$CODE_SIGN_IDENTITY" ]; then
        SIGN_ARGS+=(--sign "$CODE_SIGN_IDENTITY")
        info "使用签名身份: $CODE_SIGN_IDENTITY"
    else
        SIGN_ARGS+=(--sign -)
        warn "未找到 Apple Development / Mac Developer / Developer ID Application 签名身份，降级使用 ad-hoc 签名"
    fi

    if [ -d "$APPEX_DIR" ]; then
        info "签名 Widget Extension..."
        codesign "${SIGN_ARGS[@]}" "$APPEX_DIR" || \
            warn "Widget Extension 签名失败（非致命）"
    fi

    info "签名主 App Bundle..."
    codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE" || \
        warn "主 App 签名失败（非致命）"

    info "签名完成"
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

    create_app_bundle "$UNIVERSAL_BIN"
    sign_bundle "${PROJECT_NAME}.app"
}

build_release_xcode() {
    if [ ! -d "${PROJECT_NAME}.xcodeproj" ]; then
        warn "未找到 ${PROJECT_NAME}.xcodeproj，回退到 SwiftPM 手动构建（不会包含原生 WidgetKit 小组件）"
        build_release_universal
        return
    fi

    local xcode_build_dir="${BUILD_DIR}/xcode-release"
    local xcode_obj_dir="${xcode_build_dir}/Intermediates"
    local xcode_app="${xcode_build_dir}/Release/${PROJECT_NAME}.app"
    local xcode_widget="${xcode_app}/Contents/PlugIns/${WIDGET_APPEX}"
    local local_widget="${PROJECT_NAME}.app/Contents/PlugIns/${WIDGET_APPEX}"

    rm -rf "$xcode_build_dir" "${PROJECT_NAME}.app"

    CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
    if [ -z "$CODE_SIGN_IDENTITY" ]; then
        CODE_SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development|Mac Developer|Developer ID Application/ { print $2; exit }')
    fi

    local xcode_args=(
        -project "${PROJECT_NAME}.xcodeproj"
        -scheme "$PROJECT_NAME"
        -configuration Release
        -destination "generic/platform=macOS"
        "SYMROOT=$PWD/$xcode_build_dir"
        "OBJROOT=$PWD/$xcode_obj_dir"
        ONLY_ACTIVE_ARCH=NO
        "ARCHS=arm64 x86_64"
    )

    if [ -n "$CODE_SIGN_IDENTITY" ]; then
        xcode_args+=(
            CODE_SIGN_STYLE=Automatic
            "DEVELOPMENT_TEAM=$TEAM_ID"
            CODE_SIGN_IDENTITY="Apple Development"
        )
        info "使用 Xcode App Extension 构建并签名: $CODE_SIGN_IDENTITY"
    else
        xcode_args+=(
            CODE_SIGN_STYLE=Manual
            CODE_SIGN_IDENTITY=-
        )
        warn "未找到 Apple Development / Mac Developer / Developer ID Application 签名身份，Xcode 构建将使用 ad-hoc 签名"
    fi

    xcodebuild "${xcode_args[@]}" build

    if [ ! -d "$xcode_app" ] || [ ! -d "$xcode_widget" ]; then
        error "Xcode 构建未生成完整 App/Widget 产物"
        exit 1
    fi

    ditto "$xcode_app" "${PROJECT_NAME}.app"
    info "已复制 Xcode App Extension 产物: ${PROJECT_NAME}.app"

    if [ ! -d "${PROJECT_NAME}.app" ]; then
        error "未能在项目目录生成 ${PROJECT_NAME}.app"
        exit 1
    fi

    copy_runtime_resources "${PROJECT_NAME}.app"
    copy_widget_resources "${local_widget}"
    sign_bundle "${PROJECT_NAME}.app"

    # Xcode 会把临时构建产物注册到 LaunchServices/PluginKit。这里先移除，
    # 避免系统之后错误绑定到 .build 里的 WidgetSupport.appex。
    unregister_app_bundle "$xcode_app"
    pluginkit -r "$local_widget" 2>/dev/null || true
    rm -rf "$xcode_app"

    lipo -info "${PROJECT_NAME}.app/Contents/MacOS/${PROJECT_NAME}"
    lipo -info "${local_widget}/Contents/MacOS/${WIDGET_NAME}"
    codesign --verify --deep --strict --verbose=2 "${PROJECT_NAME}.app"
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
        cleanup_project_system_state
        build_release_xcode
        clear_widgetkit_cache
        create_dmg

        info "Release 构建完成！"
        info "App Bundle: ${PROJECT_NAME}.app"
        info "DMG: ${PROJECT_NAME}-v${MARKETING_VERSION}.dmg"
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
        SVG_FILE="Resources/app-icon.svg"
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

        mkdir -p "Resources/Assets.xcassets/AppIcon.appiconset" \
                 "Resources/Assets.xcassets/widget-icon.imageset"
        cp "${ICONSET}/icon_16x16.png" "Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16.png"
        cp "${ICONSET}/icon_16x16@2x.png" "Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png"
        cp "${ICONSET}/icon_32x32.png" "Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32.png"
        cp "${ICONSET}/icon_32x32@2x.png" "Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png"
        cp "${ICONSET}/icon_128x128.png" "Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png"
        cp "${ICONSET}/icon_128x128@2x.png" "Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png"
        cp "${ICONSET}/icon_256x256.png" "Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png"
        cp "${ICONSET}/icon_256x256@2x.png" "Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png"
        cp "${ICONSET}/icon_512x512.png" "Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png"
        cp "${ICONSET}/icon_512x512@2x.png" "Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
        cp "${ICONSET}/icon_256x256@2x.png" "Resources/Assets.xcassets/widget-icon.imageset/widget-icon.png"
        cp "${ICONSET}/icon_512x512@2x.png" "Resources/Assets.xcassets/widget-icon.imageset/widget-icon@2x.png"

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
        info "直接打开 DMG 拖入 Applications 即可安装"
        ;;

    *)
        echo "用法: $0 {debug|release|run|clean|icon|restart|dmg}"
        exit 1
        ;;
esac
