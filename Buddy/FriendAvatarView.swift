import SwiftUI
import AppKit
import Combine

struct FriendAvatarView: View {
    let friend: FriendStatus
    let theme: CharacterTheme
    @State private var showWaveBubble = false
    @State private var showMessageBubble = false
    @State private var showCallBubble = false
    @State private var bounceScale: CGFloat = 1.0
    @State private var waveFrameImage: String?
    @State private var isWaving = false
    @State private var hasUnreadMessage = false
    @State private var incomingMessageText: String?
    @State private var showFullChatBubble = false

    private var isAvailable: Bool { friend.isAvailable && friend.state == .active }

    var body: some View {
        mainContent
            .onReceive(waveLocalPublisher) { _ in showTimedIndicator($showWaveBubble) }
            .onReceive(waveRemotePublisher) { _ in playWave() }
            .onReceive(messagePublisher) { notification in handleIncomingMessage(notification) }
            .onReceive(chatOpenedPublisher) { _ in clearUnread() }
            .onReceive(callPublisher) { _ in showTimedIndicator($showCallBubble) }
    }

    // MARK: - Main layout

    private var mainContent: some View {
        VStack(spacing: 2) {
            avatarZStack
                .frame(width: 140, height: 140)
                .animation(.easeInOut(duration: 0.8), value: friend.state)
                .animation(.easeInOut(duration: 0.5), value: isAvailable)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { doWave() }
                .onTapGesture(count: 1) { playBounce() }
                .contextMenu { contextMenuItems }

            Text(friend.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 100)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.55))
                )
        }
        .scaleEffect(bounceScale * AppSettings.owlScale)
    }

    // MARK: - Avatar layers

    private var avatarZStack: some View {
        ZStack {
            if isAvailable {
                AvailableGlowView()
            }
            characterLayer
            overlayBubbles
        }
    }

    @ViewBuilder
    private var characterLayer: some View {
        if let waveImage = waveFrameImage {
            Image(waveImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 192, height: 192)
        } else {
            stateViews
        }
    }

    private var stateViews: some View {
        ZStack {
            ActiveStateView(theme: theme, isAvailable: isAvailable)
                .opacity(friend.state == .active ? 1 : 0)

            IdleStateView(theme: theme)
                .opacity(friend.state == .idle ? 1 : 0)

            ZStack {
                AsleepStateView(theme: theme)
                if friend.state == .asleep {
                    FloatingZsView()
                }
            }
            .opacity(friend.state == .asleep ? 1 : 0)
        }
    }

    @ViewBuilder
    private var overlayBubbles: some View {
        if showWaveBubble {
            IndicatorBubble(text: "\u{1F44B}")
                .offset(x: 30, y: -50)
                .transition(.scale.combined(with: .opacity))
        }
        if showFullChatBubble, let messageText = incomingMessageText {
            ChatBubbleView(text: messageText)
                .offset(x: 0, y: -65)
                .transition(.scale.combined(with: .opacity))
        } else if showMessageBubble || hasUnreadMessage {
            IndicatorBubble(text: "\u{1F4AC}")
                .offset(x: -30, y: -50)
                .transition(.scale.combined(with: .opacity))
        }
        if showCallBubble {
            IndicatorBubble(text: "\u{1F4DE}")
                .offset(x: 0, y: -55)
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Wave") { doWave() }
        Button("Chat") {
            NotificationCenter.default.post(
                name: .buddyOpenChat, object: nil,
                userInfo: ["friendId": friend.userId]
            )
        }
        Button("Call") {
            // Immediately open FaceTime on the caller's machine
            if let contact = friend.facetimeContact, !contact.isEmpty,
               let url = URL(string: "facetime://\(contact)") {
                NSWorkspace.shared.open(url)
            }
            // Send a lightweight notification to the friend
            Task { await PresenceManager.shared.sendCallRequest(to: friend.userId) }
        }
    }

    // MARK: - Publishers

    private var waveLocalPublisher: some Combine.Publisher<String, Never> {
        NotificationCenter.default.publisher(for: .buddyFriendWaved)
            .compactMap { $0.userInfo?["fromUserId"] as? String }
            .filter { $0 == friend.userId }
    }

    private var waveRemotePublisher: some Combine.Publisher<String, Never> {
        NotificationCenter.default.publisher(for: .buddyFriendWaveReceived)
            .compactMap { $0.userInfo?["fromUserId"] as? String }
            .filter { $0 == friend.userId }
    }

    private var messagePublisher: some Combine.Publisher<Notification, Never> {
        NotificationCenter.default.publisher(for: .buddyIncomingMessage)
            .filter { ($0.userInfo?["fromUserId"] as? String) == friend.userId }
    }

    private var chatOpenedPublisher: some Combine.Publisher<String, Never> {
        NotificationCenter.default.publisher(for: .buddyOpenChat)
            .compactMap { $0.userInfo?["friendId"] as? String }
            .filter { $0 == friend.userId }
    }

    private var callPublisher: some Combine.Publisher<String, Never> {
        NotificationCenter.default.publisher(for: .buddyIncomingCall)
            .compactMap { $0.userInfo?["fromUserId"] as? String }
            .filter { $0 == friend.userId }
    }

    // MARK: - Actions

    private func doWave() {
        Task { await PresenceManager.shared.sendWave(to: friend.userId) }
        NotificationCenter.default.post(
            name: .buddyFriendWaved, object: nil,
            userInfo: ["fromUserId": friend.userId]
        )
    }

    private func playWave() {
        let frames = theme.waveFrames
        guard !frames.isEmpty, !isWaving else { return }
        isWaving = true
        Task { @MainActor in
            for frame in frames {
                waveFrameImage = frame
                try? await Task.sleep(for: .milliseconds(100))
            }
            waveFrameImage = nil
            isWaving = false
        }
    }

    private func playBounce() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) {
            bounceScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                bounceScale = 1.0
            }
        }
    }

    private func handleIncomingMessage(_ notification: Notification) {
        let text = notification.userInfo?["messageText"] as? String
        incomingMessageText = text

        // Show the full chat bubble with message text
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showFullChatBubble = true
            hasUnreadMessage = true
        }

        // After 5 seconds, collapse to the small indicator
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            withAnimation(.easeOut(duration: 0.4)) {
                showFullChatBubble = false
            }
        }
    }

    private func clearUnread() {
        withAnimation(.easeOut(duration: 0.3)) {
            hasUnreadMessage = false
        }
    }

    private func showTimedIndicator(_ binding: Binding<Bool>) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            binding.wrappedValue = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                binding.wrappedValue = false
            }
        }
    }
}

private struct IndicatorBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 24))
            .padding(6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(radius: 2)
            )
    }
}

private struct ChatBubbleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.white)
            .lineLimit(3)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: 160)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.75))
                    .shadow(radius: 3)
            )
            .fixedSize(horizontal: false, vertical: true)
    }
}
