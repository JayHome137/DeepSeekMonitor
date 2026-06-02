# DeepSeek Monitor — Project Guide

macOS Menu Bar app for monitoring DeepSeek V4 Flash / Pro token usage and billing.
Swift 5.9+ / SwiftUI + AppKit / SPM / macOS 14+

## Architecture

```
MVVM:  AppDelegate → MenuBarManager → DashboardViewModel → DeepSeekService
                  ↘                    ↘ Views
                   FloatingPanel       ContentView / BalanceCardView / UsageCardsView / UsageChartView
```

- **No storyboards / XIB** — pure programmatic UI
- **No external dependencies** — Foundation + AppKit + SwiftUI + WebKit + Security only
- **LSUIElement = true** — hidden from Dock, menu bar only

## Key Files

| File | Role |
|---|---|
| `App.swift` | `@main` entry, `@MainActor AppDelegate`, system sleep/wake handling |
| `MenuBarManager.swift` | NSStatusBar + FloatingPanel (NSWindow) + NSTrackingArea hover detection + auto-close timer |
| `DashboardViewModel.swift` | `@MainActor ObservableObject`, 60s polling, balance/usage aggregation, cache, CSV import |
| `DeepSeekService.swift` | URLSession calls to `/user/balance` and `/v1/usage`, APIError enum, UserDefaults storage |
| `Theme.swift` | Brand colors, panel dimensions, card styles, gradients — all UI constants live here |
| `Models.swift` | BalanceResponse, UsageRecord, DeepSeekModel enum, usage summary models |
| `LocalCache.swift` | Dashboard state snapshot + usage records cached in UserDefaults |
| `UsageCSVImporter.swift` | Self-contained CSV parser — multi-language headers, date formats, amount/cents conversion |
| `UsageAutoImportService.swift` | Watches Downloads + usage-sync folder for new CSV/ZIP, unzips via `/usr/bin/ditto` |
| `UsageExportAutomationService.swift` | WKWebView automation — opens DeepSeek platform, JS injection to click export, download interception |
| `DirectoryChangeMonitor.swift` | `DispatchSourceFileSystemObject`-based file watcher |

## Build & Run

```bash
./build.sh icon       # Generate AppIcon.icns from SVG (requires librsvg)
./build.sh restart    # Kill old process + release build + launch
./build.sh release    # Release build → .app bundle
./build.sh dmg        # Build .app + package DMG
```

## Critical Gotchas

### Do NOT use `.buttonStyle(.plain)` in menus/popovers
Causes buttons to render gray and unresponsive in NSWindow/NSPopover + NSHostingController contexts.
Use `.buttonStyle(.borderless)` or `.buttonStyle(.borderedProminent)` instead.

### Right-click menu on status item — use performClick pattern
Persistent `statusItem.menu` binding steals left-click events. The correct pattern:
```swift
statusItem.menu = statusMenu
button.performClick(nil)
statusItem.menu = nil
```
Also: `button.sendAction(on: [.leftMouseUp, .rightMouseUp])` for explicit event handling.

### Usage endpoint may return 404
DeepSeek's `/v1/usage` is not guaranteed available. The ViewModel handles this gracefully:
- Balance query succeeds → display balance
- Usage query fails with 404 → throw `.usageEndpointUnavailable` → show warning + fallback to CSV import
- CSV import available via Settings → manual file picker + auto-detect Downloads folder

### Window level for floating panels
Use `level = .statusBar` with `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`.
Never use `NSPopover` with `NSHostingController` on macOS 14+ — event delivery is unreliable.

## Data Flow

```
DeepSeek API ─→ DeepSeekService ─→ DashboardViewModel
                   │                      │
                   ▼                      ▼
            UserDefaults          @Published props
            (LocalCache)          ─→ ContentView / MenuBarIcon
                                        │
              ┌─────────────────────────┤
              ▼                         ▼
       BalanceCardView            UsageCardsView
       UsageChartView            (tap → ModelDetailView)
```

## Token Storage

API Key: `UserDefaults.standard` key `deepseek_api_key` (domain `com.deepseek.monitor`)
Cached usage: `LocalCache` using `UserDefaults` keys `cached_dashboard` / `cached_usage_history`
Auto-import folder: `~/Library/Application Support/DeepSeekMonitor/usage-sync/`
