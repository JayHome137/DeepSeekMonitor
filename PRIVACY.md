# Privacy

DeepSeek Monitor is a local macOS utility. Data stays on your Mac unless you explicitly use DeepSeek's own web platform or API.

## API Key

The API key is stored as a generic password in the macOS login Keychain:

```text
service: com.deepseek.monitor
account: deepseek-api-key
```

When upgrading from a legacy version, the app removes the old `deepseek_api_key` UserDefaults value only after the Keychain write and readback both succeed. If migration fails, the old value remains available and the app reports the storage error without including the key.

The API key is not written into the WidgetKit App Group snapshot.

## Dashboard And Widget Data

Dashboard data is cached locally in UserDefaults so the app can show the last known state after restart.

Native WidgetKit data is shared with `WidgetSupport.appex` through the app group:

```text
N5YV5FV235.group.com.deepseek.monitor
```

The widget snapshot contains display data such as balance, availability, daily/monthly spend, V4 Flash / Pro token totals, model costs, update time, and whether native widget sync is enabled.

## Usage Data

Usage CSV or ZIP exports are processed locally. The app uses this folder for the auto-import pipeline:

```text
~/Library/Application Support/DeepSeekMonitor/usage-sync/
```

- CSV parsing happens on-device
- Parsed usage data is cached in UserDefaults
- No usage files or parsed usage data are sent to third-party services

## Network Requests

The app makes network requests only to:

- `api.deepseek.com` — balance query (`GET /user/balance`) and usage query (`GET /v1/usage`), authenticated with the configured API key
- `platform.deepseek.com` — only when automatic export is enabled in settings, using the built-in WKWebView automation window

## System Integrations

Optional settings may register a macOS login item so the app starts after sign-in and keeps widget data fresh. Native WidgetKit registration and macOS widget caches are handled by the system.

No analytics, telemetry, or third-party tracking is included.
