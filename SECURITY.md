# Security Policy

## Reporting Security Issues

If you find a security issue, please do not publish sensitive details in a public issue.

Open a private security advisory on GitHub if available, or contact the project maintainer through the repository owner profile.

## Sensitive Data

Do not commit API keys, exported usage files, local cache files, or screenshots containing private account data.

Sensitive local paths include:

```text
~/Library/Preferences/com.deepseek.monitor.plist
~/Library/Application Support/DeepSeekMonitor/usage-sync/
~/Library/Group Containers/N5YV5FV235.group.com.deepseek.monitor/
```

The WidgetKit snapshot does not include the API key, but it can include balance and usage totals. Treat it as private account data.

If an API key was accidentally committed or exposed, revoke it immediately and generate a new one from the DeepSeek platform.
