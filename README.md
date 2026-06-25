# DeepSeek Monitor

[English README](README_EN.MD) | 当前默认 README 为中文说明，英文版请查看 `README_EN.MD`。

DeepSeek Monitor 是一款 macOS 菜单栏应用，用于监控 DeepSeek V4 Flash / Pro 的账户余额、Token 用量和消费情况。当前本地发布版本为 **v1.4.7**。

需要 **macOS 14 或更高版本**；支持 **M 系列 Mac**，也支持仍可升级到 macOS 14+ 的 **Intel Mac**。

## 截图

| 原生 WidgetKit 小组件 | 菜单栏主面板 |
|---|---|
| <img src="Resources/screenshots/widget-medium.png" width="360" alt="DeepSeek Monitor 原生 WidgetKit 桌面小组件" /> | <img src="Resources/screenshots/main-panel.png" width="360" alt="DeepSeek Monitor 菜单栏主面板" /> |

| 模型详情侧页 | 设置面板 |
|---|---|
| <img src="Resources/screenshots/model-detail.png" width="350" alt="V4 Flash 模型详情侧页" /> | <img src="Resources/screenshots/settings.png" width="350" alt="DeepSeek Monitor 设置面板" /> |

## 功能

- **菜单栏主面板**：展示账户余额、账户可用状态、今日消耗、本月消费、V4 Flash / Pro 用量和 7 日 Token 趋势。
- **原生 WidgetKit 桌面小组件**：中号 macOS 小组件，使用玻璃风格 UI，展示余额、日/月消费和模型费用入口。
- **模型详情侧页**：点击 V4 Flash 或 V4 Pro 后打开与主页等宽等高的侧页，查看每日 Token 和请求次数图表。
- **小组件深链操作**：点击小组件内的模型行会直接打开对应模型详情侧页，不会先弹出完整主页。
- **用量导入兜底**：当官方用量接口不可用时，可手动导入 DeepSeek Usage CSV/ZIP，或使用监听目录自动导入。
- **自动用量导出**：可选 WKWebView 自动化，在 DeepSeek Platform 页面触发用量导出。
- **刷新间隔设置**：支持 30 秒、60 秒、2 分钟、5 分钟自动刷新。
- **开机自启**：可选注册 macOS 登录项，登录后自动启动应用并保持小组件数据更新。
- **本地缓存**：应用重启后立即显示上次数据，避免白屏。
- **本地优先**：API Key、用量缓存和小组件快照都保存在这台 Mac 上。

## 安装

### 通过 DMG 安装

打开生成的 DMG，将 `DeepSeekMonitor.app` 拖入 `/Applications`。

安装新版本后，建议从 `/Applications` 打开一次应用，让 macOS 注册 WidgetKit 扩展并刷新共享的小组件数据。如果多次本地构建后小组件选择界面仍显示旧图标，重启 macOS 可以强制 WidgetKit / IconServices 重新扫描已安装的扩展。

### 从源码构建

环境要求：

- macOS 14+；支持 M 系列 Mac，也支持可运行 macOS 14+ 的 Intel Mac
- Xcode 或 Xcode Command Line Tools
- 用于原生 WidgetKit 扩展的 Apple Development 签名身份
- 只有在运行 `./build.sh icon` 重新生成图标时才需要 `librsvg`

```bash
git clone https://github.com/JayHome137/DeepSeekMonitor.git
cd DeepSeekMonitor

# 可选：从 SVG 重新生成 AppIcon.icns 和 asset catalog 图标图片
./build.sh icon

# 在项目目录构建签名 release app 和 DMG
./build.sh release

# 构建、打包，并打开生成的 app
./build.sh restart
```

`./build.sh release` 会递增内部 build 号，在可用时通过 Xcode 构建主应用和 `WidgetSupport.appex`，签名两个 bundle，在项目根目录生成 `DeepSeekMonitor.app`，并打包 `DeepSeekMonitor-v<version>.dmg`。

只针对这个项目，release 脚本还会在打包前清理旧的 DeepSeekMonitor 系统注册和 WidgetKit / Chrono 缓存，包括旧的 `/Applications/DeepSeekMonitor.app` 副本，以避免 WidgetKit 绑定到过期的本地构建。

## 使用

1. 将 `DeepSeekMonitor.app` 安装到 `/Applications`。
2. 打开应用并点击菜单栏 DeepSeek 图标。
3. 进入设置，粘贴 DeepSeek API Key，然后点击 **验证并保存**。
4. 如需使用 macOS 桌面小组件，开启 **原生小组件数据**。
5. 在 macOS 小组件选择界面添加 **DeepSeek Monitor** 小组件。

如果你的账户无法使用 DeepSeek `/v1/usage` 接口，可以在设置里导入 CSV/ZIP 用量文件，或启用自动导出辅助功能。

## 架构

```text
AppDelegate
  -> MenuBarManager
       -> FloatingPanel / ContentView
       -> SettingsWindowController
       -> ModelDetailWindowController
  -> DashboardViewModel
       -> DeepSeekService
       -> LocalCache
            -> UserDefaults
            -> App Group snapshot
                 -> WidgetSupport TimelineProvider
                      -> WidgetViews
```

## 数据存储

- API Key：`~/Library/Preferences/com.deepseek.monitor.plist`，key 为 `deepseek_api_key`
- 主面板缓存：`cached_dashboard` / `cached_usage_history`
- 原生小组件 App Group：`N5YV5FV235.group.com.deepseek.monitor`
- 小组件相关 key：`widget_snapshot`、`native_widget_enabled`
- 自动导入目录：`~/Library/Application Support/DeepSeekMonitor/usage-sync/`

不包含分析、遥测或第三方追踪。

## 技术栈

- Swift 5.9+
- SwiftUI + AppKit + WidgetKit
- Foundation URLSession
- WKWebView 自动化
- UserDefaults + App Group shared defaults
- Shell 构建脚本：图标、签名、release 构建、DMG 打包和内部 build 号更新

## 许可证

MIT
