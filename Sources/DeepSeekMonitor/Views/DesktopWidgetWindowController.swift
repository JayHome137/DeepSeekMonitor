import Cocoa
import SwiftUI

@MainActor
final class DesktopWidgetWindowController {
    private var window: DesktopWidgetWindow?
    private let viewModel: DashboardViewModel
    private let frameKey = "desktop_widget_frame"

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(leftOf anchorFrame: NSRect? = nil, on screen: NSScreen? = nil) {
        if let window {
            position(window, leftOf: anchorFrame, on: screen)
            window.orderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: DesktopWidgetView(viewModel: viewModel))
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        let window = DesktopWidgetWindow(contentViewController: hostingController)
        position(window, leftOf: anchorFrame, on: screen)
        self.window = window
        window.onClose = { [weak self] in
            self?.saveFrame(window.frame)
            self?.window = nil
        }
        window.orderFront(nil)
    }

    func close() {
        if let window {
            saveFrame(window.frame)
        }
        window?.close()
        window = nil
    }

    private func position(_ window: NSWindow, leftOf anchorFrame: NSRect?, on screen: NSScreen?) {
        let size = NSSize(width: Theme.desktopWidgetWidth, height: Theme.desktopWidgetHeight)
        window.setContentSize(size)

        if let savedFrame = savedFrame() {
            window.setFrameOrigin(savedFrame.origin)
            return
        }

        if let anchorFrame,
           let visibleFrame = visibleFrame(containing: anchorFrame, fallback: screen) {
            var origin = NSPoint(
                x: anchorFrame.minX - size.width - Theme.desktopWidgetGap,
                y: anchorFrame.maxY - size.height
            )

            if origin.x < visibleFrame.minX + 8 {
                origin.x = visibleFrame.minX + 8
            }
            if origin.y < visibleFrame.minY + 8 {
                origin.y = visibleFrame.minY + 8
            }
            if origin.y + size.height > visibleFrame.maxY - 8 {
                origin.y = visibleFrame.maxY - size.height - 8
            }

            window.setFrameOrigin(origin)
            return
        }

        guard let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame else {
            window.center()
            return
        }

        window.setFrameOrigin(NSPoint(
            x: visibleFrame.maxX - size.width - 24,
            y: visibleFrame.maxY - size.height - 52
        ))
    }

    private func visibleFrame(containing frame: NSRect, fallback screen: NSScreen?) -> NSRect? {
        if let screen, screen.frame.intersects(frame) {
            return screen.visibleFrame
        }

        return NSScreen.screens.first { $0.frame.intersects(frame) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
    }

    private func saveFrame(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: frameKey)
    }

    private func savedFrame() -> NSRect? {
        guard let rawValue = UserDefaults.standard.string(forKey: frameKey) else { return nil }
        let frame = NSRectFromString(rawValue)
        guard frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }
}

private final class DesktopWidgetWindow: NSPanel {
    var onClose: (() -> Void)?

    init(contentViewController: NSViewController) {
        super.init(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: Theme.desktopWidgetWidth, height: Theme.desktopWidgetHeight)
            ),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentViewController = contentViewController
        self.contentViewController?.view.wantsLayer = true
        self.contentViewController?.view.layer?.cornerRadius = Theme.desktopWidgetCornerRadius
        self.contentViewController?.view.layer?.masksToBounds = true
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = Theme.desktopWidgetCornerRadius
        self.contentView?.layer?.masksToBounds = true
        self.contentView?.superview?.wantsLayer = true
        self.contentView?.superview?.layer?.cornerRadius = Theme.desktopWidgetCornerRadius
        self.contentView?.superview?.layer?.masksToBounds = true
        self.level = .normal
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func close() {
        super.close()
        onClose?()
    }
}
