import AppKit
import SwiftUI
import Combine
import Sparkle
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var companionPanel: CompanionPanel!
    private var friendPanelManager: FriendPanelManager!
    private var chatManager: ChatManager!
    private var eventCancellable: AnyCancellable?
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prompt for display name before starting presence (so registration uses it)
        promptForDisplayNameIfNeeded()

        ActivityMonitor.shared.start()
        PresenceManager.shared.start()

        companionPanel = CompanionPanel()
        companionPanel.orderFront(nil)

        friendPanelManager = FriendPanelManager()
        friendPanelManager.start()

        chatManager = ChatManager()
        chatManager.start()

        observeIncomingEvents()

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            print("[DEBUG] === All windows ===")
            for window in NSApplication.shared.windows {
                print("[DEBUG] Window: \(type(of: window)), title: '\(window.title)', frame: \(window.frame), isVisible: \(window.isVisible), ignoresMouseEvents: \(window.ignoresMouseEvents), level: \(window.level.rawValue)")
            }
            print("[DEBUG] === End windows ===")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ActivityMonitor.shared.stop()
        PresenceManager.shared.stop()
        friendPanelManager.stop()
        chatManager.stop()
    }

    private func observeIncomingEvents() {
        eventCancellable = PresenceManager.shared.$pendingEvents
            .receive(on: RunLoop.main)
            .sink { [weak self] events in
                self?.processEvents(events)
            }
    }

    private func processEvents(_ events: [BuddyEvent]) {
        for event in events {
            switch event.eventType {
            case "wave":
                print("[Buddy] Received wave from \(event.fromUserId) (\(event.fromDisplayName))")

                // Play wave animation on the friend's avatar (not our own owl)
                NotificationCenter.default.post(
                    name: .buddyFriendWaveReceived,
                    object: nil,
                    userInfo: ["fromUserId": event.fromUserId]
                )

            case "call":
                handleIncomingCall(from: event)

            default:
                break
            }

            PresenceManager.shared.consumeEvent(event)
        }
    }

    // MARK: - Call handling

    private func handleIncomingCall(from event: BuddyEvent) {
        // Show call indicator on the friend's avatar
        NotificationCenter.default.post(
            name: .buddyIncomingCall,
            object: nil,
            userInfo: ["fromUserId": event.fromUserId]
        )

        // Show a system notification — FaceTime itself handles the actual incoming call UI
        let content = UNMutableNotificationContent()
        content.title = "Incoming Call"
        content.body = "\(event.fromDisplayName) is calling you via FaceTime"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "call-\(event.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Updates

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    // MARK: - One-time prompts

    private func promptForDisplayNameIfNeeded() {
        let presence = PresenceManager.shared
        guard presence.displayName.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "What should your friends see you as?"
        alert.informativeText = "This name appears under your owl on your friends' desktops."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Skip")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "Your name"
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                presence.displayName = name
            }
        }
    }

}
