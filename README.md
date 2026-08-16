# DeepSeek Monitor

[English](README_EN.MD)

DeepSeek Monitor 是一款 macOS 菜单栏应用，用于查看 DeepSeek V4 Flash / Pro 的账户余额、Token 用量和消费数据。当前版本为 **v1.5.1**。

需要 **macOS 14 或更高版本**；支持 Apple Silicon，也支持可运行 macOS 14+ 的 Intel Mac。

## 核心功能

- 菜单栏主面板展示账户余额、今日/本月消费、模型用量和近 7 日 Token 趋势。
- 原生 WidgetKit 中号小组件同步关键数据，点击模型可直接打开详情侧页。
- 自动网页导出按设定频率静默同步本月用量；首次登录或登录失效时才显示网页窗口。
- 支持手动导入 DeepSeek 官方本月、近 7 日或近 30 日 Usage ZIP/CSV，作为网页变化、登录失效和历史补录的兜底。
- 支持余额定时刷新、开机自启、本地缓存和手动检查软件更新。

## 界面

| 主面板 | 模型详情 | 原生小组件 | 设置 |
|---|---|---|---|
| <img src="Resources/screenshots/main-panel.png" width="240" alt="菜单栏主面板" /> | <img src="Resources/screenshots/model-detail.png" width="240" alt="模型详情" /> | <img src="Resources/screenshots/widget-medium.png" width="300" alt="原生 WidgetKit 小组件" /> | <img src="Resources/screenshots/settings.png" width="240" alt="设置" /> |

## 安装

### Homebrew

```bash
brew install --cask JayHome137/tap/deepseekmonitor
```

### DMG

从 [GitHub Releases](https://github.com/JayHome137/DeepSeekMonitor/releases) 下载 DMG，将 `DeepSeekMonitor.app` 拖入 `/Applications`，然后从“应用程序”打开一次。

### 从源码构建

需要 Xcode 或 Xcode Command Line Tools，以及用于主应用和 WidgetKit 扩展的 Apple Development 签名身份。

```bash
git clone https://github.com/JayHome137/DeepSeekMonitor.git
cd DeepSeekMonitor

./build.sh run      # 构建并运行 Debug App
./build.sh release  # 生成 DeepSeekMonitor.app 和 DMG
```

发布者可运行 `./build.sh signed-release`，在构建 DMG 后生成并验证 Sparkle 签名 Appcast。该命令要求发布私钥已保存在 macOS 登录钥匙串中；私钥不得写入仓库。

## 使用

1. 打开应用并点击菜单栏 DeepSeek 图标。
2. 在设置中粘贴 DeepSeek API Key，然后点击“验证并保存”。
3. 如需用量同步，首次手动登录 DeepSeek 平台后启用自动导出；也可以直接导入官方 Usage ZIP/CSV。
4. 如需桌面小组件，启用“原生小组件数据”，再从 macOS 小组件库添加 DeepSeek Monitor。

DeepSeek `/v1/usage` 对部分账户可能返回 404，但不影响余额查询。此时应用使用官方网页导出或手动导入补充用量；ZIP 会同时读取 `amount.csv` 和 `cost.csv`。统计日期以导出文件的时区为准，网页数据可能延迟约 5 分钟。

## 软件更新

在设置中点击“检查更新”即可手动查询新版本。应用不会在后台自动检查或安装更新；更新源仅允许 HTTPS，并使用 Sparkle Ed25519 签名验证 Appcast 和 DMG。

## 安全与隐私

- DeepSeek API Key 保存在 macOS 登录钥匙串，不写入配置文件或小组件共享数据。
- 用量缓存、导入文件处理结果和小组件快照仅保存在本机。
- Sparkle 发布私钥仅保存在发布者钥匙串中，仓库和应用内只包含公钥。
- 不包含分析、遥测或第三方追踪。

## 许可证

MIT
