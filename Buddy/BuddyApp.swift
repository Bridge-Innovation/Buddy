import SwiftUI
import Sparkle

@main
struct BuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var monitor = ActivityMonitor.shared
    @ObservedObject private var presence = PresenceManager.shared
    @State private var friendCodeInput = ""
    @State private var isEditingName = false
    @State private var owlSize: Int = AppSettings.owlSize
    @State private var newCallLabel = "FaceTime"
    @State private var newCallURL = ""

    private let callLabelOptions = ["FaceTime", "WhatsApp", "Discord", "Zoom", "Google Meet", "Skype", "Other"]

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 4) {
                Label(monitor.state.rawValue, systemImage: monitor.state.icon)
                    .font(.headline)

                if isEditingName {
                    HStack {
                        TextField("Your name", text: $presence.displayName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                            .onSubmit { isEditingName = false }
                        Button("Done") { isEditingName = false }
                            .font(.caption)
                    }
                } else {
                    HStack {
                        Text(presence.displayName.isEmpty ? "No name set" : presence.displayName)
                            .foregroundStyle(presence.displayName.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button("Edit") { isEditingName = true }
                            .font(.caption)
                    }
                }

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

                Picker("Owl Size", selection: $owlSize) {
                    Text("Small").tag(0)
                    Text("Medium").tag(1)
                    Text("Large").tag(2)
                }
                .onChange(of: owlSize) { _, newValue in
                    AppSettings.owlSize = newValue
                }

                Divider()

                // Call links
                Text("Call Links")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let callLinks = PresenceManager.parseCallLinks(from: presence.facetimeContact)
                ForEach(callLinks, id: \.url) { link in
                    HStack {
                        Text(link.label)
                        Text(link.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Remove") {
                            var updated = callLinks.filter { $0.url != link.url }
                            if updated.isEmpty {
                                presence.facetimeContact = ""
                            } else {
                                presence.facetimeContact = PresenceManager.serializeCallLinks(updated)
                            }
                        }
                        .font(.caption)
                    }
                }

                HStack {
                    Picker("", selection: $newCallLabel) {
                        ForEach(callLabelOptions, id: \.self) { Text($0) }
                    }
                    .frame(width: 90)
                    TextField("URL", text: $newCallURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                    Button("Add") {
                        let url = newCallURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !url.isEmpty else { return }
                        var links = callLinks
                        links.append(CallLink(label: newCallLabel, url: url))
                        presence.facetimeContact = PresenceManager.serializeCallLinks(links)
                        newCallURL = ""
                    }
                    .disabled(newCallURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

                Button("Check for Updates...") {
                    appDelegate.checkForUpdates()
                }

                Button("Quit Buddy") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(4)
        } label: {
            Image(systemName: monitor.state.icon)
        }
        .menuBarExtraStyle(.window)
    }
}
