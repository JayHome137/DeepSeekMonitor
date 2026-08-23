# Security policy

## Supported versions

Security fixes are provided for the latest published release of DeepSeek Monitor. Reproduce a suspected issue on the latest release before reporting it whenever possible.

| Version | Supported |
| --- | --- |
| Latest published release (`1.5.2`) | Yes |
| Older releases | No |

## Reporting a security issue

Do not disclose vulnerability details, proof-of-concept code, API keys, exported usage files, or private account data in a public issue.

Use **Security > Advisories > Report a vulnerability** in the GitHub repository when private vulnerability reporting is available. If that button is unavailable, open a public issue containing only a request to establish private contact. Do not include technical vulnerability details in that issue.

Include the following information in the private report:

- The affected DeepSeek Monitor and macOS versions.
- The affected feature and expected security boundary.
- Minimal reproduction steps and the observed impact.
- Redacted logs, screenshots, or sample files needed to reproduce the issue.
- Whether the issue is already public or has been disclosed to another party.

Use synthetic data wherever possible. Never include a working API key or another person's account data. Allow the maintainer a reasonable opportunity to investigate and release a fix before public disclosure.

## Security boundaries

DeepSeek Monitor applies the following controls in the latest release:

- API keys are stored in the macOS login Keychain and are removed from legacy UserDefaults only after a verified Keychain write.
- API keys are not written to WidgetKit shared data, usage exports, logs, or the web export session.
- Web export main-frame navigation and native bridge messages are restricted to HTTPS `platform.deepseek.com` origins.
- Imported ZIP and CSV sources are validated before processing. Archive checks reject unsafe paths, duplicate entries, symbolic links, special files, malformed metadata, and files that exceed configured size or extraction limits.
- Automatic export downloads and import archives are limited to 64 MiB before processing.
- Software updates use HTTPS-only URLs and Sparkle Ed25519 signatures for the Appcast and update artifact. Signature verification is required before extraction.
- The Sparkle signing private key is kept in the maintainer's Keychain and is not stored in the repository or app. The public verification key embedded in the app is not a secret.
- Background update checks, automatic update installation, and Sparkle system profiling are disabled.

These controls reduce risk but do not make arbitrary files, web content, or compromised developer credentials trustworthy. Reports that identify a way to bypass one of these boundaries are in scope.

## Sensitive local data

Do not commit API keys, exported usage files, local cache files, WKWebView website data, or screenshots containing private account data.

Sensitive local locations include:

```text
macOS login Keychain: service com.deepseek.monitor, account deepseek-api-key
~/Library/Application Support/DeepSeekMonitor/usage-sync/
~/Library/Group Containers/N5YV5FV235.group.com.deepseek.monitor/
```

Legacy releases stored the API key in `~/Library/Preferences/com.deepseek.monitor.plist` under `deepseek_api_key`. Current releases migrate that value to Keychain and remove it only after a verified write and readback.

The WidgetKit snapshot does not include the API key, but it can include balance and usage totals. Treat it as private account data.

## Credential exposure

If an API key is accidentally committed, logged, or otherwise exposed, revoke it immediately and generate a new key from the DeepSeek platform. Removing the value from the latest commit is not sufficient because it can remain in Git history, forks, caches, and local clones.

If a Sparkle release signing key or Apple signing credential may have been exposed, stop publishing updates, rotate the affected credential, review previously published artifacts, and communicate the impact through a repository security advisory.
