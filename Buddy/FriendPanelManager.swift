import AppKit
import SwiftUI
import Combine

@MainActor
final class FriendPanelManager {
    private var panels: [String: NSPanel] = [:] // friendId → panel
    private var cancellable: AnyCancellable?
    private let panelSize = CGSize(width: 150, height: 170)

    func start() {
        cancellable = PresenceManager.shared.$friends
            .receive(on: RunLoop.main)
            .sink { [weak self] friends in
                self?.syncPanels(with: friends)
            }
    }

    func stop() {
        cancellable?.cancel()
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    private func syncPanels(with friends: [FriendStatus]) {
        let currentFriendIds = Set(friends.map(\.userId))
        let existingIds = Set(panels.keys)

        // Remove panels for friends who went offline
        for id in existingIds.subtracting(currentFriendIds) {
            panels[id]?.orderOut(nil)
            panels.removeValue(forKey: id)
        }

        // Add panels for new online friends
        for friend in friends where !existingIds.contains(friend.userId) {
            let panel = createFriendPanel(for: friend)
            panels[friend.userId] = panel
            panel.orderFront(nil)
        }

        // Update existing panels with new friend data
        for friend in friends {
            if let panel = panels[friend.userId] {
                updatePanel(panel, with: friend)
            }
        }
    }

    private func createFriendPanel(for friend: FriendStatus) -> NSPanel {
        let origin = positionForNewPanel()

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true

        // Accept clicks for double-tap wave gesture
        panel.setValue(true, forKey: "canBecomeKey")

        let theme = CharacterType.from(serverValue: friend.characterType).theme
        let hostingView = NSHostingView(rootView:
            FriendAvatarView(friend: friend, theme: theme)
        )
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView

        return panel
    }

    private func updatePanel(_ panel: NSPanel, with friend: FriendStatus) {
        let theme = CharacterType.from(serverValue: friend.characterType).theme
        let hostingView = NSHostingView(rootView:
            FriendAvatarView(friend: friend, theme: theme)
        )
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView
    }

    private func positionForNewPanel() -> CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: 400, y: 100)
        }

        let screenFrame = screen.visibleFrame
        let existingCount = panels.count
        let spacing: CGFloat = 20
        let startX = screenFrame.maxX - panelSize.width - 40

        // Stack along the bottom-right, moving left for each additional friend
        let x = startX - CGFloat(existingCount) * (panelSize.width + spacing)
        let y = screenFrame.minY + 20

        return CGPoint(x: x, y: y)
    }
}
