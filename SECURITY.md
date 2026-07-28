# Security Policy

## Reporting Security Issues

If you find a security issue, please do not publish sensitive details in a public issue.

Open a private security advisory on GitHub if available, or contact the project maintainer through the repository owner profile.

## Sensitive Data

Do not commit API keys, exported usage files, local cache files, or screenshots containing private account data.

Sensitive local paths include:

```text
macOS login Keychain: service com.deepseek.monitor, account deepseek-api-key
~/Library/Application Support/DeepSeekMonitor/usage-sync/
~/Library/Group Containers/N5YV5FV235.group.com.deepseek.monitor/
```

Legacy releases stored the API key in `~/Library/Preferences/com.deepseek.monitor.plist` under `deepseek_api_key`. Current releases migrate that value to Keychain and remove it only after a verified write.

The WidgetKit snapshot does not include the API key, but it can include balance and usage totals. Treat it as private account data.

If an API key was accidentally committed or exposed, revoke it immediately and generate a new one from the DeepSeek platform.
