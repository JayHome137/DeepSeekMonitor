import SwiftUI
import AppKit

struct ClickableRow: NSViewRepresentable {
    let onTap: () -> Void

    func makeNSView(context: Context) -> NSView {
        let button = NSButton(frame: .zero)
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.title = ""
        button.target = context.coordinator
        button.action = #selector(Coordinator.handleTap)
        button.autoresizingMask = [.width, .height]
        return button
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Ensure button fills available space
        if let superview = nsView.superview {
            nsView.frame = superview.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject {
        let onTap: () -> Void
        init(onTap: @escaping () -> Void) { self.onTap = onTap }
        @objc func handleTap() { onTap() }
    }
}

extension View {
    func onNSButtonTap(perform action: @escaping () -> Void) -> some View {
        self.overlay(ClickableRow(onTap: action))
    }
}
