# Privacy

DeepSeek Monitor is designed as a local macOS utility.

## API Key

The API Key is stored only on the current Mac through macOS preferences:

```text
~/Library/Preferences/com.deepseek.monitor.plist
```

The preference key used by the app is:

```text
deepseek_api_key
```

## Usage Data

Usage CSV or ZIP exports are processed locally. The app uses this local folder for automatic import:

```text
~/Library/Application Support/DeepSeekMonitor/usage-sync/
```

The app parses usage files locally for display and does not send parsed usage files to a third-party service.

## Network Requests

The app uses the configured API Key to request DeepSeek account data from DeepSeek API endpoints.

Automatic web export may open the DeepSeek platform page and interact with the export flow when enabled by the user.
