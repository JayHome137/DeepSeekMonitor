import Cocoa
import SwiftUI

@MainActor
final class ModelDetailWindowController: NSObject {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<ModelDetailView>?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let viewModel: DashboardViewModel

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var visibleFrame: CGRect? {
        guard let panel, panel.isVisible else { return nil }
        return panel.frame
    }

    func show(for model: DeepSeekModel, anchoredTo anchorWindow: NSWindow) {
        show(for: model, anchoredTo: anchorWindow.frame, screen: anchorWindow.screen, dismissAnchorWindow: anchorWindow)
    }

    func show(for model: DeepSeekModel, anchoredTo anchorFrame: NSRect, screen: NSScreen?) {
        show(for: model, anchoredTo: anchorFrame, screen: screen, dismissAnchorWindow: nil)
    }

    private func show(for model: DeepSeekModel, anchoredTo anchorFrame: NSRect, screen: NSScreen?, dismissAnchorWindow: NSWindow?) {
        let rootView = ModelDetailView(viewModel: viewModel, model: model)

        if let panel, let hostingController {
            hostingController.rootView = rootView
            layout(panel: panel, anchoredTo: anchorFrame, screen: screen)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            installDismissMonitorsIfNeeded(anchorWindow: dismissAnchorWindow)
            return
        }

        let hostingController = NSHostingController(rootView: rootView)
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Theme.detailPanelWidth,
                height: Theme.detailPanelHeight
            ),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = Theme.panelCornerRadius
        panel.contentView?.layer?.masksToBounds = true

        self.hostingController = hostingController
        self.panel = panel

        layout(panel: panel, anchoredTo: anchorFrame, screen: screen)
        panel.orderFrontRegardless()
        installDismissMonitorsIfNeeded(anchorWindow: dismissAnchorWindow)
    }

    func close() {
        panel?.orderOut(nil)
        removeDismissMonitors()
    }

    private func layout(panel: NSPanel, nextTo anchorWindow: NSWindow) {
        layout(panel: panel, anchoredTo: anchorWindow.frame, screen: anchorWindow.screen)
    }

    private func layout(panel: NSPanel, anchoredTo anchorFrame: NSRect, screen: NSScreen?) {
        panel.setContentSize(NSSize(width: Theme.detailPanelWidth, height: Theme.detailPanelHeight))

        guard let screen = screen ?? NSScreen.main else { return }

        // Position to the right of anchor, centered vertically
        var origin = NSPoint(
            x: anchorFrame.maxX + Theme.detailPanelGap,
            y: anchorFrame.midY - Theme.detailPanelHeight / 2
        )

        // If no room on right, try left
        if origin.x + Theme.detailPanelWidth > screen.visibleFrame.maxX - 6 {
            origin.x = anchorFrame.minX - Theme.detailPanelWidth - Theme.detailPanelGap
        }

        // If no room on either side, center on screen
        if origin.x < screen.visibleFrame.minX + 6 {
            origin.x = max(screen.visibleFrame.minX + 6, anchorFrame.midX - Theme.detailPanelWidth / 2)
        }

        // Clamp vertical position
        if origin.y < screen.visibleFrame.minY + 6 {
            origin.y = screen.visibleFrame.minY + 6
        }
        if origin.y + Theme.detailPanelHeight > screen.visibleFrame.maxY - 6 {
            origin.y = screen.visibleFrame.maxY - Theme.detailPanelHeight - 6
        }

        panel.setFrameOrigin(origin)
    }

    private func installDismissMonitorsIfNeeded(anchorWindow: NSWindow?) {
        guard localMonitor == nil, globalMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }

            if event.window?.windowNumber == panel.windowNumber {
                return event
            }

            if let anchorWindow, event.window?.windowNumber == anchorWindow.windowNumber {
                self.close()
                return event
            }

            self.close()
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func removeDismissMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }
}
