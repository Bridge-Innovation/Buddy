import AppKit
import SwiftUI
import Combine

@MainActor
final class ChatManager {
    nonisolated(unsafe) private var chatPanels: [String: NSPanel] = [:] // friendId → panel
    private var cancellables = Set<AnyCancellable>()

    func start() {
        // Listen for "open chat" requests from friend avatar context menus
        NotificationCenter.default.publisher(for: .buddyOpenChat)
            .compactMap { $0.userInfo?["friendId"] as? String }
            .receive(on: RunLoop.main)
            .sink { [weak self] friendId in
                self?.openChat(with: friendId)
            }
            .store(in: &cancellables)

        // Listen for incoming messages to show indicator or open chat
        PresenceManager.shared.$incomingMessages
            .receive(on: RunLoop.main)
            .sink { [weak self] messages in
                self?.handleIncomingMessages(messages)
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        for panel in chatPanels.values {
            panel.orderOut(nil)
        }
        chatPanels.removeAll()
    }

    private func openChat(with friendId: String) {
        // If already open, bring to front
        if let existing = chatPanels[friendId] {
            existing.orderFront(nil)
            return
        }

        guard let friend = PresenceManager.shared.friends.first(where: { $0.userId == friendId }) else {
            return
        }

        let myTheme = ActivityMonitor.shared.characterType.theme
        let friendTheme = CharacterType.from(serverValue: friend.characterType).theme

        let chatView = ChatView(friend: friend, myTheme: myTheme, friendTheme: friendTheme)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 380),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = NSColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1.0)
        panel.minSize = NSSize(width: 220, height: 280)
        panel.hasShadow = true

        // Position near the friend's avatar or center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 140
            let y = screenFrame.midY - 190
            panel.setFrameOrigin(CGPoint(x: x, y: y))
        }

        let hostingView = NSHostingView(rootView: chatView)
        panel.contentView = hostingView

        // Track when the user closes the panel
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.chatPanels.removeValue(forKey: friendId)
        }

        chatPanels[friendId] = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func handleIncomingMessages(_ messages: [ChatMessage]) {
        // For each sender, either route to open chat or post notification for avatar indicator
        var senderIds = Set<String>()
        for msg in messages {
            senderIds.insert(msg.fromUserId)
        }

        for senderId in senderIds {
            // Find the latest message text from this sender
            let latestText = messages.last(where: { $0.fromUserId == senderId })?.message

            var userInfo: [String: Any] = ["fromUserId": senderId]
            if let text = latestText {
                userInfo["messageText"] = text
            }

            if chatPanels[senderId] != nil {
                // Chat is open — notify the ChatView to pick up messages
                NotificationCenter.default.post(
                    name: .buddyIncomingMessage,
                    object: nil,
                    userInfo: userInfo
                )
            } else {
                // Chat not open — show indicator on friend avatar
                NotificationCenter.default.post(
                    name: .buddyIncomingMessage,
                    object: nil,
                    userInfo: userInfo
                )
            }
        }
    }
}
