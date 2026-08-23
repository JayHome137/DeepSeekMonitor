# Privacy

DeepSeek Monitor is a local macOS utility. Account and usage data stay on your Mac except when the app communicates with DeepSeek at your request, runs usage export automation that you enabled, or checks for and installs a software update.

## API key

The API key is stored as a generic password in the macOS login Keychain:

```text
service: com.deepseek.monitor
account: deepseek-api-key
```

When upgrading from a legacy version, the app removes the old `deepseek_api_key` UserDefaults value only after the Keychain write and readback both succeed. If migration fails, the old value remains available and the app reports the storage error without including the key.

The API key is used only for authenticated requests to the DeepSeek API. It is not injected into the web export session, written to usage files, or included in the WidgetKit App Group snapshot.

## Dashboard, usage, and widget data

Dashboard snapshots and parsed usage history are cached locally in UserDefaults so the app can show the last known state after restart or while the network is unavailable.

Native WidgetKit data is shared with `WidgetSupport.appex` through the app group:

```text
N5YV5FV235.group.com.deepseek.monitor
```

The widget snapshot can contain balance, availability, daily and monthly spend, V4 Flash and Pro token totals, model costs, update time, and whether native widget sync is enabled. It does not contain the API key, but the snapshot is still private account data.

## Usage files

Official usage CSV or ZIP exports are parsed on-device. Automatic exports use this local folder:

```text
~/Library/Application Support/DeepSeekMonitor/usage-sync/
```

The folder has the following lifecycle:

- `incoming/` receives automatic export files. The latest successfully processed source can remain there until a newer source replaces it or the user removes it.
- `workspace/` contains the CSV files prepared for the current import. It is cleared when the next import is prepared.
- `failed/` retains files that could not be imported so they can be inspected or retried. These files are not deleted automatically by age.

Manual imports are read from the location selected by the user. The app does not upload source files or parsed usage data to another service.

## Web export data

Usage export automation uses a built-in WKWebView with the default persistent website data store. DeepSeek sign-in cookies and other website data can therefore remain on this Mac so later exports can reuse the login session.

Main-frame navigation is restricted to HTTPS pages on `platform.deepseek.com`. The DeepSeek page can load its own supporting resources and API requests as part of the website session. The app does not send the configured DeepSeek API key to this web session.

## Network requests

Depending on the feature used, the app can contact:

- `api.deepseek.com` for balance (`GET /user/balance`) and usage (`GET /v1/usage`) requests authenticated with the configured API key.
- `platform.deepseek.com` and resources used by that page for sign-in and official usage export automation.
- `raw.githubusercontent.com` to retrieve the signed Sparkle Appcast when the user manually checks for updates.
- GitHub release delivery hosts to download an update after the user accepts it.

Software update checks are manual. Background update checks and automatic installation are disabled. Sparkle system profiling is disabled, so the app does not add a system profile to update requests. GitHub and DeepSeek can still receive normal network metadata, such as the source IP address, when their services are contacted.

## System integrations

Optional settings can register a macOS login item so the app starts after sign-in and keeps widget data fresh. Native WidgetKit registration and macOS widget caches are handled by the system.

## Removing local data

- Use **Clear Key** (`清除 Key`) in Settings to remove the API key from Keychain and reset the app's account state.
- Clearing the business cache removes dashboard and usage caches and resets the WidgetKit snapshot, but keeps the API key and user settings.
- Clearing the business cache does not remove WKWebView cookies or other website data and does not delete every file under `usage-sync/`.
- Files retained in `incoming/` or `failed/` must be removed by the user when they are no longer needed.

No analytics, telemetry, advertising SDK, or third-party tracking is included.
