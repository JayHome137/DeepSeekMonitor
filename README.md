# 📊 DeepSeek Monitor

**面向 macOS 的 DeepSeek 账户余额、用量与消费监控工具。**

[English](README_EN.MD)

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-111827?logo=apple&logoColor=white)
![Architecture](https://img.shields.io/badge/architecture-Apple%20Silicon%20%7C%20Intel-555555)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)
![WidgetKit](https://img.shields.io/badge/WidgetKit-medium-007AFF)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

> [!IMPORTANT]
> 本项目仅支持 **macOS 14 或更高版本**，支持 Apple Silicon，也支持仍可升级到 macOS 14+ 的 Intel Mac。本项目不是 DeepSeek 官方产品；API Key、网页登录状态和用量数据均属于用户自己的私密数据。

## 📌 项目介绍

DeepSeek Monitor 是一款菜单栏应用，集中显示账户余额、Token 用量、模型成本和近期趋势。模型用量按官方 Usage 导出的 `model` 标识分为 **V4.1 Flash**（`deepseek-flash`）与 **V4 Flash**（`deepseek-v4-flash`）两类。

余额优先通过 DeepSeek API 获取；当 `/v1/usage` 对账户返回 404，或网页数据需要补充时，应用使用 DeepSeek 官方 Usage ZIP/CSV 导出。网页自动导出只在用户启用后运行，定时任务保持静默；首次登录或登录失效时才显示网页窗口。

## ✅ 适用环境

| 项目 | 支持情况 | 说明 |
| --- | --- | --- |
| 操作系统 | macOS 14+ | 仅支持 macOS |
| 处理器 | Apple Silicon / Intel | Intel Mac 需能运行 macOS 14 或更高版本 |
| 运行方式 | 菜单栏应用 | `LSUIElement`，不会显示在 Dock |
| 原生小组件 | WidgetKit medium | 仅支持中号小组件 |
| 网络 | DeepSeek API / 官方网页 | 更新检查另需访问 GitHub 发布源 |

## 🎯 能做什么

- 菜单栏主面板显示余额、今日/本月消费、模型用量和近 7 日 Token 趋势。
- 原生 WidgetKit 中号小组件同步关键数据，点击模型可打开详情侧页。
- 按设定频率静默导出并导入本月用量；登录失效时提示用户重新登录。
- 手动导入 DeepSeek 官方本月、近 7 天、近 30 天或历史 Usage ZIP/CSV。
- 余额定时刷新、本地缓存、登录时自动启动和手动检查软件更新。
- ZIP 导入前执行路径、重复条目、符号链接、特殊文件和大小限制校验。

## 🖼️ 界面预览

| 主面板 | 模型详情 | 原生小组件 | 设置 |
|---|---|---|---|
| <img src="Resources/screenshots/main-panel.png" width="240" alt="菜单栏主面板" /> | <img src="Resources/screenshots/model-detail.png" width="240" alt="模型详情" /> | <img src="Resources/screenshots/widget-medium.png" width="300" alt="原生 WidgetKit 小组件" /> | <img src="Resources/screenshots/settings.png" width="240" alt="设置" /> |

## 🚀 快速开始

### 直接安装

从 [GitHub Releases](https://github.com/JayHome137/DeepSeekMonitor/releases) 下载 DMG，将 `DeepSeekMonitor.app` 拖入 `/Applications`，然后从“应用程序”打开一次。

### Homebrew

```bash
brew install --cask JayHome137/tap/deepseekmonitor
```

### 首次使用

1. 打开应用并点击菜单栏 DeepSeek 图标。
2. 在“设置”中粘贴 DeepSeek API Key，点击“验证并保存”。
3. 如需同步用量，打开登录页登录 DeepSeek 平台，再启用自动导出；也可以直接导入官方 Usage ZIP/CSV。
4. 如需桌面小组件，启用“原生小组件数据”，再从 macOS 小组件库添加 DeepSeek Monitor。

## ⚙️ 工作机制

```text
DeepSeek API ───────────────┐
                            ▼
官方网页导出 ZIP/CSV ──> 本地校验与解析 ──> 用量聚合
                                                │
                                                ▼
                              UserDefaults 本地缓存
                                      ┌─────────┴─────────┐
                                      ▼                   ▼
                               菜单栏 Dashboard      WidgetKit 快照
```

核心原则：

1. **官方数据优先**：余额使用 API；用量使用 API 或官方导出文件，不猜测网页数据。
2. **本地处理**：CSV/ZIP 在本机解析，导入结果写入本地缓存，不上传到第三方服务。
3. **静默同步**：自动导出只在用户启用后运行，后台任务不主动打开网页窗口。
4. **安全边界**：网页主框架仅允许 HTTPS `platform.deepseek.com`；导入文件先校验再处理。
5. **签名更新**：更新源仅允许 HTTPS，Sparkle 在安装前验证签名 Appcast 和 DMG。

## 📥 用量同步与限制

- DeepSeek `/v1/usage` 对部分账户可能返回 404，但不影响余额查询；应用会回退到官方网页导出或手动导入。
- 自动同步只处理官方当前月份 ZIP；近 7 天、近 30 天和历史数据使用手动导入。
- 当前官方 ZIP 包含 `amount-YYYY-MM-DD_YYYY-MM-DD.csv` 与 `cost-YYYY-MM-DD_YYYY-MM-DD.csv`，两者日期范围和时区必须匹配。`amount` CSV 字段为 `user_id`、`start_time_iso`、`end_time_iso`、`model`、`api_key_name`、`api_key`、`type`、`price`、`amount`；`cost` CSV 字段为 `user_id`、`start_time_iso`、`end_time_iso`、`model`、`wallet_type`、`cost`、`currency`。
- 两张模型卡代表导出记录中的两个 `model` 标识。V4.1 Flash 是新模型；V4 Flash 是旧模型名，原模型已下线，旧名称的 API 请求由 V4.1 Flash 提供服务并按 Flash 价格计费。V4 Pro 仍由官方提供服务，仅不在本应用当前面板展示范围内；如果导出范围内有 Pro 用量，原始 CSV 可能包含 Pro 行，应用会按当前面板范围跳过这些行。
- 费用以官方导出的 `cost` 为准；分时单价和模型计费规则请以 [DeepSeek 官方定价页](https://api-docs.deepseek.com/zh-cn/quick_start/pricing/) 为准，应用不会用本地硬编码价格覆盖官方费用。
- 统计日期以官方导出文件携带的时区为准，网页数据可能延迟约 5 分钟。
- 自动导入失败的文件会保留在 `usage-sync/failed/`，不会静默删除，方便排查或重新导入；官方原始文件可能含有 `api_key` 列，请按敏感文件保管。

## 🛠️ 从源码构建

需要 Xcode 或 Xcode Command Line Tools，以及用于主应用和 WidgetKit 扩展的 Apple Development 签名身份。

```bash
git clone https://github.com/JayHome137/DeepSeekMonitor.git
cd DeepSeekMonitor

swift test             # 运行 Swift Package 测试
./build.sh run         # 构建并运行稳定签名的 Debug App
./build.sh release     # 生成 DeepSeekMonitor.app 和 DMG
```

发布者可运行：

```bash
./build.sh signed-release
```

该命令会构建 Release、生成 DMG，并使用 macOS 登录钥匙串中的 Sparkle 私钥生成和验证签名 Appcast。发布私钥不得写入仓库。

构建产物位于仓库根目录：

```text
DeepSeekMonitor.app
DeepSeekMonitor-v<version>.dmg
```

CI 等价的无签名构建：

```bash
xcodebuild \
  -project DeepSeekMonitor.xcodeproj \
  -scheme DeepSeekMonitor \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .build/ci-derived \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

## 🔐 安全与隐私

- API Key 保存在 macOS 登录钥匙串，不写入应用缓存、WidgetKit 共享数据或日志。官方 `amount` 导出可能自带 `api_key` 列；应用只识别导入所需字段并忽略该列，不会把它写入缓存、Widget 快照或诊断信息。
- WKWebView 使用本机持久化网站数据保存 DeepSeek 登录状态；清空业务缓存不会自动清除网页 Cookie。
- 自动导出下载和 ZIP 导入均有 64 MiB 限制，并在解压前拒绝路径穿越、重复条目、符号链接和特殊文件。
- 软件更新使用 Sparkle Ed25519 签名验证；仓库和 App 内只有公钥，发布私钥仅保存在维护者钥匙串。
- 不包含分析、遥测、广告 SDK 或第三方追踪。

详细说明：

- [隐私政策](./PRIVACY.md)
- [安全策略](./SECURITY.md)

## 📁 仓库内容

```text
Sources/DeepSeekMonitor/       主应用、菜单栏界面、API、网页导出与导入逻辑
Sources/WidgetSupport/         WidgetKit 扩展
Resources/screenshots/         README 界面截图
Resources/Info.plist           App 身份、版本和 Sparkle 信任配置
appcast.xml                    Sparkle 签名更新清单
build.sh                       构建、签名、DMG 和 Appcast 工具
tests/                         API Key、用量导入、图标和 ViewModel 测试
PRIVACY.md                     隐私政策
SECURITY.md                    安全策略
```

## 🤝 共建与反馈

欢迎提交脱敏后的 macOS 版本、App 版本和复现步骤。请勿上传 API Key、Cookie、密码、完整导出文件、数据库、完整用户路径或未脱敏截图。

安全问题请先阅读 [安全策略](./SECURITY.md)，不要在公开 Issue 中披露漏洞细节。

## 📜 许可证

Copyright © 2026 JayHome137。

本项目以 **MIT License** 发布，完整条款见 [LICENSE](./LICENSE)。本项目不提供任何明示或暗示担保；DeepSeek、Apple、Sparkle 等名称和商标归各自权利人所有。

## ⚠️ 免责声明

本项目是社区维护的 macOS 工具，并非 DeepSeek 或 Apple 的官方产品。网页结构、API 行为和导出格式可能变化；遇到导入失败或数据不一致时，请保留原始官方导出文件并使用手动导入或提交脱敏复现信息。
