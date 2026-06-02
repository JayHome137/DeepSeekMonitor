import Cocoa
import SwiftUI

// MARK: - Settings Window Controller
//
// 管理设置窗口的创建、显示和生命周期。
// 复用单个窗口实例，关闭时释放，再次打开重建。

final class SettingsWindowController: NSObject {
    private var window: NSWindow?
    private let viewModel: DashboardViewModel
    private let sideGap: CGFloat = 14

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    /// 打开（或切换到）设置窗口
    @MainActor
    func show(anchorTo anchorWindow: NSWindow? = nil) {
        if let window = window, window.isVisible {
            position(window, nextTo: anchorWindow)
            bringToFront(window)
            return
        }

        let settingsView = SettingsView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: settingsView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        let window = SettingsPanel(contentViewController: hostingController)
        window.title = "设置"
        window.setContentSize(NSSize(width: 420, height: 660))
        window.styleMask = [.borderless, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        position(window, nextTo: anchorWindow)
        window.delegate = self

        self.window = window
        bringToFront(window)
    }

    @MainActor
    func show(anchorFrame: NSRect?, screen: NSScreen?) {
        if let window = window, window.isVisible {
            position(window, nextTo: anchorFrame, on: screen)
            bringToFront(window)
            return
        }

        show(anchorTo: nil)
        if let window {
            position(window, nextTo: anchorFrame, on: screen)
        }
    }

    @MainActor
    private func position(_ window: NSWindow, nextTo anchorWindow: NSWindow?) {
        guard let anchorWindow else {
            window.center()
            return
        }

        let anchorFrame = anchorWindow.frame
        guard let screen = anchorWindow.screen ?? NSScreen.main else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size

        var origin = NSPoint(
            x: anchorFrame.maxX + sideGap,
            y: anchorFrame.maxY - windowSize.height
        )

        if origin.x + windowSize.width > visibleFrame.maxX - 8 {
            origin.x = anchorFrame.minX - windowSize.width - sideGap
        }

        if origin.x < visibleFrame.minX + 8 {
            origin.x = min(
                max(visibleFrame.minX + 8, anchorFrame.midX - windowSize.width / 2),
                visibleFrame.maxX - windowSize.width - 8
            )
        }

        if origin.y < visibleFrame.minY + 8 {
            origin.y = visibleFrame.minY + 8
        }

        if origin.y + windowSize.height > visibleFrame.maxY - 8 {
            origin.y = visibleFrame.maxY - windowSize.height - 8
        }

        window.setFrameOrigin(origin)
    }

    @MainActor
    private func position(_ window: NSWindow, nextTo anchorFrame: NSRect?, on screen: NSScreen?) {
        guard let anchorFrame else {
            window.center()
            return
        }

        let screen = screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let windowSize = window.frame.size
        var origin = NSPoint(
            x: anchorFrame.maxX + sideGap,
            y: anchorFrame.maxY - windowSize.height
        )

        if origin.x + windowSize.width > visibleFrame.maxX - 8 {
            origin.x = anchorFrame.minX - windowSize.width - sideGap
        }

        if origin.x < visibleFrame.minX + 8 {
            origin.x = min(
                max(visibleFrame.minX + 8, anchorFrame.midX - windowSize.width / 2),
                visibleFrame.maxX - windowSize.width - 8
            )
        }

        if origin.y < visibleFrame.minY + 8 {
            origin.y = visibleFrame.minY + 8
        }

        if origin.y + windowSize.height > visibleFrame.maxY - 8 {
            origin.y = visibleFrame.maxY - windowSize.height - 8
        }

        window.setFrameOrigin(origin)
    }

    @MainActor
    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.orderFrontRegardless()
    }
}

private final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - NSWindowDelegate

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
