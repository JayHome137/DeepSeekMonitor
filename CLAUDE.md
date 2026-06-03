# DeepSeek Monitor — Project Guide

macOS menu bar app for monitoring DeepSeek V4 Flash / Pro token usage and billing.
Swift 5.9+ / SwiftUI + AppKit + WidgetKit / SPM + Xcode project / macOS 14+

## Architecture

```text
AppDelegate -> MenuBarManager -> FloatingPanel / SettingsWindow / ModelDetailWindow
            -> DashboardViewModel -> DeepSeekService / LocalCache
            -> WidgetSupport reads App Group snapshot
```

- No storyboards / XIB: pure programmatic UI.
- No third-party runtime dependencies: Foundation, AppKit, SwiftUI, WidgetKit, WebKit, Security, ServiceManagement.
- `LSUIElement = true`: hidden from Dock, menu bar only.
- App bundle id: `com.deepseek.monitor`.
- Widget bundle id: `com.deepseek.monitor.widget`.
- App Group: `N5YV5FV235.group.com.deepseek.monitor`.

## Key Files

| File | Role |
|---|---|
| `Sources/DeepSeekMonitor/App.swift` | `@main` entry, sleep/wake and deep-link handling. |
| `Sources/DeepSeekMonitor/MenuBarManager.swift` | NSStatusBar, main panel, settings/detail routing, widget deep links, hover auto-close. |
| `Sources/DeepSeekMonitor/ViewModels/DashboardViewModel.swift` | Polling, balance/usage aggregation, cache, CSV import flow. |
| `Sources/DeepSeekMonitor/Services/DeepSeekService.swift` | DeepSeek API calls and API key storage. |
| `Sources/DeepSeekMonitor/Services/LocalCache.swift` | Dashboard cache and WidgetKit App Group snapshot. |
| `Sources/DeepSeekMonitor/Views/ContentView.swift` | Main menu bar dashboard. |
| `Sources/DeepSeekMonitor/Views/ModelDetailWindowController.swift` | V4 Flash / Pro side panel, same size as dashboard. |
| `Sources/DeepSeekMonitor/Views/SettingsView.swift` | API key, native widget sync, login item, refresh/import/export settings. |
| `Sources/WidgetSupport/TimelineProvider.swift` | WidgetKit timeline provider reading shared data. |
| `Sources/WidgetSupport/WidgetViews.swift` | Medium WidgetKit UI, glass styling, model shortcuts. |
| `Resources/Assets.xcassets/` | App/widget image assets compiled into app and appex. |
| `build.sh` | Version bump, Xcode release build, signing, WidgetKit cleanup, DMG packaging. |

## Build & Run

```bash
./build.sh icon       # Generate AppIcon.icns and asset catalog icon images from SVG.
./build.sh release    # Increment build, build signed app + appex, create app and DMG in project root.
./build.sh restart    # Run release, then open the generated project-root app.
./build.sh dmg        # Run release and print DMG install guidance.
```

Release outputs stay in the project root: `DeepSeekMonitor.app` and `DeepSeekMonitor-v<version>-build<build>.dmg`. Do not assume release installs into `/Applications`. The script may remove stale `/Applications/DeepSeekMonitor.app` for this project only, then leaves installation to the user via the DMG.

## Critical Gotchas

### Native WidgetKit signing

WidgetKit extensions on macOS 26 need a trusted Apple Development certificate. Xcode automatic signing is used when available. The app and appex must both carry `N5YV5FV235.group.com.deepseek.monitor`.

### Widget data and cache

The app writes `widget_snapshot` and `native_widget_enabled` into the App Group. `WidgetSupport` reads them in `TimelineProvider`. `build.sh release` clears DeepSeekMonitor-specific PluginKit/LaunchServices registrations, Chrono cache, relevance cache, and stale app copies. If the widget gallery keeps an old icon after repeated local builds, reboot macOS to force WidgetKit/IconServices to rescan `/Applications/DeepSeekMonitor.app`.

### Icons

After `actool`, `build.sh` copies `Resources/AppIcon.icns` back into both app and appex so the full `ic12` icon remains available for LaunchServices and WidgetKit.

### Widget families and deep links

Only `.systemMedium` is supported. The old small widget and old hand-written desktop widget window are removed. Widget row taps use `deepseekmonitor://flash` and `deepseekmonitor://pro`, and should open only the model detail side panel.

### Detail panel sizing

`Theme.detailPanelWidth = Theme.panelWidth` and `Theme.detailPanelHeight = Theme.panelDashboardHeight`. Any model-detail trigger should go through `ModelDetailWindowController` so dashboard clicks and widget deep links stay aligned.

### Buttons and status menu

Avoid `.buttonStyle(.plain)` for menu/popover controls that need reliable hit testing; prefer `.borderless` or `.borderedProminent`. Right-click status item menus must use the temporary `statusItem.menu` + `button.performClick(nil)` pattern, then set `statusItem.menu = nil`.

### Usage endpoint fallback

DeepSeek's `/v1/usage` can return 404. Balance should still display, and usage should fall back to CSV/ZIP import or WKWebView export automation.

## Data Storage

- API key: `~/Library/Preferences/com.deepseek.monitor.plist`, key `deepseek_api_key`.
- Dashboard cache: `cached_dashboard`, `cached_usage_history`.
- Widget App Group: `~/Library/Group Containers/N5YV5FV235.group.com.deepseek.monitor/`, keys `widget_snapshot`, `native_widget_enabled`.
- Auto-import folder: `~/Library/Application Support/DeepSeekMonitor/usage-sync/`.
