# DeepSeek Monitor

[中文说明](README_CN.md)

DeepSeek Monitor is an unofficial macOS menu bar app for viewing DeepSeek account balance and local usage trends.

This project is not affiliated with DeepSeek.

## Features

- Menu bar access to a compact DeepSeek usage panel.
- Displays account balance, current-day cost, and current-month cost.
- Parses exported DeepSeek usage CSV or ZIP files locally.
- Supports automatic export/import workflow for usage data.
- Shows model-level usage trends for V4 Flash and V4 Pro.
- Keeps API Key data on the current Mac only.

## Requirements

- macOS 14 or later.
- Apple Silicon and Intel Mac are both supported through the packaged Universal Binary.
- Swift 5.9 or later.
- Xcode Command Line Tools.

## Build

```bash
swift build -c release
```

## Package DMG

```bash
./build.sh dmg
```

The packaged DMG is generated as:

```text
DeepSeekMonitor-v1.2.0.dmg
```

## Local Data

API Key is stored locally through macOS preferences:

```text
~/Library/Preferences/com.deepseek.monitor.plist
```

Usage export files are processed inside the app's local Application Support folder:

```text
~/Library/Application Support/DeepSeekMonitor/usage-sync/
```

See [PRIVACY.md](PRIVACY.md) for details.

## License

MIT License. See [LICENSE](LICENSE).
