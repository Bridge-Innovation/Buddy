import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var companionPanel: CompanionPanel!
    private var friendPanelManager: FriendPanelManager!
    private var eventCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ActivityMonitor.shared.start()
        PresenceManager.shared.start()

        companionPanel = CompanionPanel()
        companionPanel.orderFront(nil)

        friendPanelManager = FriendPanelManager()
        friendPanelManager.start()

        observeIncomingEvents()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ActivityMonitor.shared.stop()
        PresenceManager.shared.stop()
        friendPanelManager.stop()
    }

    private func observeIncomingEvents() {
        eventCancellable = PresenceManager.shared.$pendingEvents
            .receive(on: RunLoop.main)
            .sink { [weak self] events in
                self?.processEvents(events)
            }
    }

    private func processEvents(_ events: [BuddyEvent]) {
        for event in events where event.eventType == "wave" {
            // Play wave animation on the user's own character
            NotificationCenter.default.post(name: .buddyIncomingWave, object: nil)

            // Show wave bubble on the friend's avatar
            NotificationCenter.default.post(
                name: .buddyFriendWaved,
                object: nil,
                userInfo: ["fromUserId": event.fromUserId]
            )

            // Play a subtle sound
            NSSound.beep()

            // Consume so it doesn't repeat
            PresenceManager.shared.consumeEvent(event)
        }
    }
}
