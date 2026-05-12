# DeepSeek Monitor

DeepSeek Monitor 是一个非官方 macOS 菜单栏工具，用来查看 DeepSeek 账户余额和本地用量趋势。

本项目不是 DeepSeek 官方项目，也不隶属于 DeepSeek。

## 功能

- 在 macOS 菜单栏快速打开 DeepSeek 用量面板。
- 显示账户余额、当日消耗、本月消费。
- 本地解析 DeepSeek 导出的 CSV 或 ZIP 用量文件。
- 支持自动导出和自动导入用量数据。
- 支持查看 V4 Flash 和 V4 Pro 的模型用量趋势。
- API Key 只保存在当前这台 Mac 本地。

## 环境要求

- macOS 14 或更高版本。
- Swift 5.9 或更高版本。
- Xcode Command Line Tools。

## 构建

```bash
swift build -c release
```

## 打包 DMG

```bash
./build.sh dmg
```

打包完成后会生成：

```text
DeepSeekMonitor-v1.1.1.dmg
```

## 本地数据位置

API Key 通过 macOS Preferences 保存在本地：

```text
~/Library/Preferences/com.deepseek.monitor.plist
```

用量导出文件会在应用的本地 Application Support 目录中处理：

```text
~/Library/Application Support/DeepSeekMonitor/usage-sync/
```

更多隐私说明见 [PRIVACY.md](PRIVACY.md)。

## 开源协议

本项目使用 MIT License，详见 [LICENSE](LICENSE)。
