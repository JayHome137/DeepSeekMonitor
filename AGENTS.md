# DeepSeek Monitor - Project guide

DeepSeek Monitor is a macOS menu bar app for monitoring DeepSeek account balance,
token usage, model costs, and recent usage trends. It also provides a native
WidgetKit widget, official usage-export import, silent browser-assisted syncing,
and manually initiated signed software updates.

This is the repository's only agent instruction file. Do not recreate
`CLAUDE.md` or maintain a second copy of this guide.

## Platform and dependencies

- Swift 5.9+, SwiftUI, AppKit, WidgetKit, WebKit, Security, and ServiceManagement.
- macOS 14 or later; release builds target both Apple Silicon and Intel.
- Sparkle 2.9.5 is the only third-party runtime dependency.
- No storyboards or XIB files; application UI is programmatic.
- `LSUIElement = true`: the app is menu-bar-only and hidden from the Dock.
- App bundle ID: `com.deepseek.monitor`.
- Widget bundle ID: `com.deepseek.monitor.widget`.
- App Group: `N5YV5FV235.group.com.deepseek.monitor`.

Treat these files as the version source of truth:

- `build.sh`: marketing version used by release tooling.
- `Resources/Info.plist`: app marketing version and build number.
- `Sources/WidgetSupport/Info.plist`: widget marketing version and build number.

The app and widget versions must always match. Do not hard-code the current
release version elsewhere in this guide.

## Architecture

```text
AppDelegate -> MenuBarManager -> FloatingPanel / SettingsWindow / ModelDetailWindow
            -> DashboardViewModel -> DeepSeekService -> APIKeyStore -> Keychain
                                  -> UsageCSVImporter / UsageAutoImportService
                                  -> LocalCache -> App Group -> WidgetSupport
            -> UsageExportAutomationService -> WKWebView -> official usage ZIP
            -> SoftwareUpdateController -> Sparkle -> signed appcast.xml
```

- `DashboardViewModel` owns refresh scheduling, visible dashboard state, usage
  aggregation, import orchestration, cache writes, and widget snapshots.
- Balance comes from the DeepSeek API. The `/v1/usage` endpoint may return 404;
  usage then comes from official ZIP/CSV exports.
- `UsageExportAutomationService` reuses the user's DeepSeek web session and keeps
  scheduled exports hidden. The login window is shown only for an explicit login
  action or when the user needs to restore the session.
- `WidgetSupport` reads the App Group snapshot and never reads the API key.

## Key files

| File | Responsibility |
|---|---|
| `Sources/DeepSeekMonitor/App.swift` | App entry point, sleep/wake handling, and deep-link dispatch. |
| `Sources/DeepSeekMonitor/MenuBarManager.swift` | Status item, main panel, settings/detail routing, hover behavior, and status menu. |
| `Sources/DeepSeekMonitor/ViewModels/DashboardViewModel.swift` | Refresh, aggregation, cache, import, and widget synchronization. |
| `Sources/DeepSeekMonitor/Services/DeepSeekService.swift` | Balance/usage API requests and in-process API-key access. |
| `Sources/DeepSeekMonitor/Services/APIKeyStore.swift` | Keychain storage and verified legacy migration. |
| `Sources/DeepSeekMonitor/Services/UsageExportAutomationService.swift` | Official-site WKWebView login, silent export, and download handling. |
| `Sources/DeepSeekMonitor/Services/UsageAutoImportService.swift` | ZIP/CSV preparation, archive validation, quarantine, and automatic import state. |
| `Sources/DeepSeekMonitor/Services/UsageCSVImporter.swift` | Official amount/cost schema parsing and aggregation. |
| `Sources/DeepSeekMonitor/Services/SoftwareUpdateController.swift` | Manual Sparkle update checks and user-visible update state. |
| `Sources/DeepSeekMonitor/Services/LocalCache.swift` | Dashboard cache and WidgetKit App Group snapshot. |
| `Sources/DeepSeekMonitor/Views/ContentView.swift` | Main menu bar dashboard. |
| `Sources/DeepSeekMonitor/Views/SettingsView.swift` | API key, widget, login item, update, refresh, and import/export settings. |
| `Sources/DeepSeekMonitor/Views/ModelDetailWindowController.swift` | Flash/Pro model detail side panel. |
| `Sources/WidgetSupport/TimelineProvider.swift` | Widget timeline provider reading shared data. |
| `Sources/WidgetSupport/WidgetViews.swift` | Medium WidgetKit UI and deep links. |
| `Resources/Assets.xcassets/DeepSeekMenuBarTemplate.imageset/` | Native 1x/2x template menu bar icon. |
| `Resources/Info.plist` | App identity, version, URL scheme, and Sparkle trust configuration. |
| `appcast.xml` | Sparkle-signed published update feed. |
| `.github/workflows/ci.yml` | Tests, unsigned release build, trust checks, and menu icon validation. |
| `build.sh` | Version bump, Xcode build, signing, cleanup, DMG, and appcast packaging. |

## Build and verify

```bash
swift test
./build.sh run
./build.sh release
./build.sh appcast
./build.sh signed-release
```

- `swift test` runs the package tests without creating release artifacts.
- `./build.sh run` increments the build number, creates a stable development-signed
  Xcode Debug app, verifies its Team ID, and opens it.
- `./build.sh release` increments the build number, builds the universal app and
  widget, signs nested Sparkle components, verifies the bundle, and creates the DMG.
- `./build.sh appcast` signs the existing matching DMG and does not increment the
  build number.
- `./build.sh signed-release` runs `release` followed by `appcast`.

Release outputs stay in the repository root:

```text
DeepSeekMonitor.app
DeepSeekMonitor-v<version>.dmg
```

The CI-equivalent unsigned build is:

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

## Release boundaries

- `./build.sh release` changes both Info.plist build numbers. Do not rerun it only
  to publish an already validated artifact; doing so breaks the source/DMG/appcast
  pairing.
- Before publishing, confirm the app, widget, `build.sh`, DMG name, and appcast all
  describe the same marketing version and build number.
- The appcast may retain earlier published versions, but it must not contain an
  unpublished build. Its enclosure URL, byte length, and Ed25519 signature must
  match the uploaded DMG.
- The Sparkle private key stays in the maintainer's login Keychain. Only the public
  key belongs in `Resources/Info.plist` and the repository.
- Do not commit, push, create a tag or GitHub Release, close issues, or update the
  separate Homebrew tap unless the user explicitly authorizes that operation.
- A release is not complete until the remote tag/commit, uploaded DMG hash and
  size, raw appcast, and GitHub CI result have been verified.

## Security and data boundaries

### API key

The API key is a generic password in the macOS login Keychain with service
`com.deepseek.monitor` and account `deepseek-api-key`. Legacy migration must keep
this invariant:

```text
read legacy value -> write Keychain -> read back and verify -> remove legacy value
```

Any failure must leave the legacy value available. Never put the API key in logs,
UserDefaults, widget snapshots, diagnostics, test fixtures, or release notes.

### Official usage export

- Browser automation and script messages are restricted to main-frame HTTPS pages
  on `platform.deepseek.com`.
- Automatic browser exports must remain silent; explicit login actions may show the
  WKWebView window.
- Downloads and import sources are limited to 64 MiB before extraction.
- ZIP validation must continue to reject traversal, absolute/backslash paths,
  duplicate entries, symbolic links, special files, excessive entries, and
  oversized extracted data.
- Automatic sync accepts only official current-month ZIP exports. Manual import is
  the fallback for official month, recent-range, and historical ZIP/CSV files.
- Amount and cost files must describe compatible ranges and time-zone semantics.

### Software updates

- Update checks are manual; automatic checks and automatic installation are off.
- The feed and download URLs are HTTPS-only.
- Sparkle verifies the signed appcast and the downloaded DMG before extraction.
- Do not weaken `SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`,
  `SUEnableInstallerLauncherService`, or `SUAllowedURLSchemes`.

## UI and WidgetKit invariants

- The menu bar image comes from `DeepSeekMenuBarTemplate.imageset`: 18x18 pixels at
  1x and 36x36 pixels at 2x, with template rendering enabled. Do not restore the old
  oversized runtime PNG or manually override the image representation size.
- Keep `MenuBarIconTests` and the CI `assetutil` checks when changing menu icon
  loading or asset catalog configuration.
- Avoid `.buttonStyle(.plain)` for menu/popover controls that need reliable hit
  testing; use `.borderless` or `.borderedProminent` as appropriate.
- Right-click status menus must temporarily assign `statusItem.menu`, invoke
  `button.performClick(nil)`, and then clear `statusItem.menu`.
- Only `.systemMedium` is supported. Widget links use
  `deepseekmonitor://settings`, `deepseekmonitor://flash`, and
  `deepseekmonitor://pro`.
- Dashboard and widget model links must route through
  `ModelDetailWindowController`; the detail panel remains the same size as the main
  dashboard.
- Because this is an `LSUIElement` app, UI tools may report no windows while the app
  is running normally with all panels closed. Verify the process and status item
  before treating a window-attachment timeout as a launch failure.

## Local data

- Dashboard cache: `cached_dashboard`, `cached_usage_history`, and the history
  schema version in standard UserDefaults.
- Widget data: `widget_snapshot` and `native_widget_enabled` in
  `~/Library/Group Containers/N5YV5FV235.group.com.deepseek.monitor/`.
- Managed usage imports:
  `~/Library/Application Support/DeepSeekMonitor/usage-sync/`.
- Failed automatic imports are quarantined under the managed usage-sync directory;
  do not silently discard them before the UI reports the failure.

## Validation expectations

- Documentation-only changes: run `git diff --check` and verify every documented
  path and command against the repository.
- Shared logic or user-visible changes: run `swift test` and the CI-equivalent
  Xcode build.
- Menu icon changes: run `MenuBarIconTests`, inspect the compiled asset catalog,
  and verify light/dark AppKit rendering on the supported macOS version.
- Release changes: additionally verify `codesign --deep --strict`, `hdiutil verify`,
  Sparkle appcast signatures, remote artifact hash/size, and GitHub CI.
