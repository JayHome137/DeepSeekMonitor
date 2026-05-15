# Privacy

DeepSeek Monitor is a local macOS utility. All data stays on your Mac unless explicitly chosen otherwise.

## API Key

The API Key is stored locally via macOS UserDefaults under the key `deepseek_api_key`. The preferences domain is `com.deepseek.monitor`:

```
~/Library/Preferences/com.deepseek.monitor.plist
```

## Usage Data

Usage CSV or ZIP exports (manual import or automatic download) are processed locally. The app uses this folder for the auto-import pipeline:

```
~/Library/Application Support/DeepSeekMonitor/usage-sync/
```

- CSV parsing happens entirely on-device
- Parsed usage data is cached in UserDefaults for display after restart
- No usage files or parsed data are sent to any third-party service

## Network Requests

The app makes network requests only to:

- `api.deepseek.com` — balance query (`GET /user/balance`) and usage query (`GET /v1/usage`), authenticated with the configured API Key
- `platform.deepseek.com` — only when the user enables automatic export in settings (WKWebView-based automation)

No analytics, telemetry, or third-party tracking of any kind.
