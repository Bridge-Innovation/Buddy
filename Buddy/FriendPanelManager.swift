import AppKit
import SwiftUI
import Combine

@MainActor
final class FriendPanelManager {
    private var panels: [String: FriendPanel] = [:]
    private var cancellable: AnyCancellable?
    private var hiddenFriends: Set<String> = []
    private var previousOnlineFriends: Set<String> = []

    private var panelSize: CGSize {
        let scale = AppSettings.owlScale
        return CGSize(width: 180 * scale, height: 260 * scale)
    }

    func start() {
        cancellable = PresenceManager.shared.$friends
            .receive(on: RunLoop.main)
            .sink { [weak self] friends in
                self?.syncPanels(with: friends)
            }

        NotificationCenter.default.addObserver(
            forName: .buddyHideFriend, object: nil, queue: .main
        ) { [weak self] notification in
            guard let friendId = notification.userInfo?["friendId"] as? String else { return }
            self?.hideFriend(friendId)
        }
    }

    func stop() {
        cancellable?.cancel()
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    func hideFriend(_ friendId: String) {
        hiddenFriends.insert(friendId)
        if let panel = panels[friendId] {
            animateOut(panel) { [weak self] in
                self?.panels.removeValue(forKey: friendId)
            }
        }
    }

    func showFriend(_ friendId: String) {
        hiddenFriends.remove(friendId)
        syncPanels(with: PresenceManager.shared.friends)
    }

    var hiddenFriendIds: Set<String> { hiddenFriends }

    private func syncPanels(with friends: [FriendStatus]) {
        print("[FPM] syncPanels called with \(friends.count) friends, existing panels: \(panels.count)")
        let currentFriendIds = Set(friends.map(\.userId))
        let existingIds = Set(panels.keys)

        // Unhide friends that went offline and came back online
        for fId in hiddenFriends {
            if !previousOnlineFriends.contains(fId) && currentFriendIds.contains(fId) {
                hiddenFriends.remove(fId)
            }
        }
        previousOnlineFriends = currentFriendIds

        for id in existingIds.subtracting(currentFriendIds) {
            if let panel = panels[id] {
                animateOut(panel) { [weak self] in
                    self?.panels.removeValue(forKey: id)
                }
            }
        }

        for friend in friends where !existingIds.contains(friend.userId) && !hiddenFriends.contains(friend.userId) {
            print("[FPM] Creating panel for \(friend.displayName)")
            let panel = createFriendPanel(for: friend)
            panels[friend.userId] = panel
            showPanel(panel)
        }
    }

    // MARK: - Show panel (animation disabled for debugging)

    private func showPanel(_ panel: NSPanel) {
        print("[FPM] showPanel: NSScreen.main?.frame = \(String(describing: NSScreen.main?.frame))")
        let finalOrigin: CGPoint
        if AppSettings.isTestUser2 {
            finalOrigin = CGPoint(x: 200, y: 500)
        } else {
            finalOrigin = CGPoint(x: 200, y: 200)
        }
        print("[FPM] showPanel: placing panel at \(finalOrigin)")
        panel.setFrameOrigin(finalOrigin)
        panel.alphaValue = 1
        panel.orderFront(nil)
        panel.setFrameOrigin(finalOrigin)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            panel.setFrameOrigin(finalOrigin)
            print("[FPM] showPanel: after delay, panel.frame = \(panel.frame)")
        }
    }

    private func animateOut(_ panel: NSPanel, completion: @escaping () -> Void) {
        guard let screen = NSScreen.main else {
            panel.orderOut(nil)
            completion()
            return
        }

        let offScreenX = screen.frame.maxX + 20
        let origin = panel.frame.origin

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(CGPoint(x: offScreenX, y: origin.y))
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            completion()
        })
    }

    // MARK: - Panel creation

    private func createFriendPanel(for friend: FriendStatus) -> FriendPanel {
        let origin = positionForNewPanel()
        let panel = FriendPanel(origin: origin, size: panelSize, friendId: friend.userId)

        let theme = CharacterType.from(serverValue: friend.characterType).theme
        let hostingView = NSHostingView(rootView:
            FriendAvatarView(friend: friend, theme: theme)
        )
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView

        return panel
    }

    private func positionForNewPanel() -> CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: 400, y: 100)
        }

        let screenFrame = screen.visibleFrame
        let existingCount = panels.count
        let spacing: CGFloat = 20

        let x: CGFloat
        if AppSettings.isTestUser2 {
            x = screenFrame.minX + 40 + CGFloat(existingCount) * (panelSize.width + spacing)
        } else {
            let startX = screenFrame.maxX - panelSize.width - 40
            x = startX - CGFloat(existingCount) * (panelSize.width + spacing)
        }
        let y = screenFrame.minY + 20

        return CGPoint(x: x, y: y)
    }
}

// MARK: - Friend Panel (mirrors CompanionPanel's event handling exactly)

final class FriendPanel: NSPanel {
    let friendId: String

    init(origin: CGPoint, size: CGSize, friendId: String) {
        self.friendId = friendId
        super.init(
            contentRect: NSRect(origin: origin, size: size),
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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setFrameOrigin(_ point: NSPoint) {
        print("[FriendPanel] setFrameOrigin(\(point)) called from:", Thread.callStackSymbols.prefix(6).joined(separator: "\n  "))
        super.setFrameOrigin(point)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        print("[FriendPanel] setFrame(\(frameRect)) called from:", Thread.callStackSymbols.prefix(6).joined(separator: "\n  "))
        super.setFrame(frameRect, display: displayFlag)
    }

    override func becomeKey() {
        super.becomeKey()
        DispatchQueue.main.async { [weak self] in
            self?.resignKey()
        }
    }
}
