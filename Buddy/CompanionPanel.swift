import AppKit
import SwiftUI

final class CompanionPanel: NSPanel {
    private static let positionXKey = "CompanionPanelX"
    private static let positionYKey = "CompanionPanelY"

    init() {
        let defaultOrigin = AppSettings.isTestUser2
            ? CGPoint(x: 500, y: 200)
            : CGPoint(x: 200, y: 200)
        let origin = Self.savedOrigin ?? defaultOrigin

        let scale = AppSettings.owlScale
        super.init(
            contentRect: NSRect(origin: origin, size: CGSize(width: 192 * scale, height: 192 * scale)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true

        let hostingView = NSHostingView(rootView:
            CompanionView()
                .environmentObject(ActivityMonitor.shared)
        )
        hostingView.layer?.backgroundColor = .clear
        contentView = hostingView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    // Accept clicks for tap/double-tap gestures, but never steal main window status
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Resign key immediately so we don't keep focus from the user's active app
    override func becomeKey() {
        super.becomeKey()
        DispatchQueue.main.async { [weak self] in
            self?.resignKey()
        }
    }

    @objc private func windowDidMove(_ notification: Notification) {
        let origin = frame.origin
        AppSettings.defaults.set(Double(origin.x), forKey: Self.positionXKey)
        AppSettings.defaults.set(Double(origin.y), forKey: Self.positionYKey)
    }

    private static var savedOrigin: CGPoint? {
        let defaults = AppSettings.defaults
        guard defaults.object(forKey: positionXKey) != nil else { return nil }
        return CGPoint(
            x: defaults.double(forKey: positionXKey),
            y: defaults.double(forKey: positionYKey)
        )
    }
}
