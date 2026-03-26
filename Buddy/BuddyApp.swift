import SwiftUI

@main
struct BuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var monitor = ActivityMonitor.shared
    @ObservedObject private var presence = PresenceManager.shared
    @State private var friendCodeInput = ""

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 4) {
                Label(monitor.state.rawValue, systemImage: monitor.state.icon)
                    .font(.headline)

                if let code = presence.friendCode {
                    HStack {
                        Text("My code:")
                            .foregroundStyle(.secondary)
                        Text(code)
                            .font(.system(.body, design: .monospaced).bold())
                            .textSelection(.enabled)
                    }
                }

                Divider()

                Toggle("Available to cowork", isOn: $monitor.isAvailableToCowork)

                Picker("Character", selection: $monitor.characterType) {
                    Text("Owl 1").tag(CharacterType.owl1)
                    Text("Owl 2").tag(CharacterType.owl2)
                }

                Divider()

                // Friends list
                if !presence.friends.isEmpty {
                    Text("Friends")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(presence.friends) { friend in
                        HStack {
                            Image(systemName: friend.state.icon)
                                .foregroundStyle(friend.isAvailable ? .green : .secondary)
                            Text(friend.displayName)
                            Spacer()
                            Text(friend.activityState)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()
                }

                // Add friend
                HStack {
                    TextField("Friend code", text: $friendCodeInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Button("Add") {
                        let code = friendCodeInput
                        friendCodeInput = ""
                        Task { await presence.addFriend(code: code) }
                    }
                    .disabled(friendCodeInput.count != 6)
                }

                Divider()

                Button("Quit Buddy") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(4)
        } label: {
            Image(systemName: monitor.state.icon)
        }
    }
}
