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
    @State private var hasMissedCall = false
    @State private var incomingMessageText: String?
    @State private var showFullChatBubble = false

    private var isAvailable: Bool { friend.isAvailable && friend.state == .active }

    var body: some View {
        mainContent
            .onReceive(waveLocalPublisher) { _ in showTimedIndicator($showWaveBubble) }
            .onReceive(waveRemotePublisher) { _ in playWave() }
            .onReceive(messagePublisher) { notification in handleIncomingMessage(notification) }
            .onReceive(chatOpenedPublisher) { _ in clearUnread() }
            .onReceive(callPublisher) { _ in handleIncomingCall() }
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
            SpeechBubbleView(text: messageText)
                .offset(x: 0, y: -70)
                .transition(.scale.combined(with: .opacity))
        } else if hasUnreadMessage {
            SmallSpeechBubble()
                .offset(x: -30, y: -50)
                .transition(.scale.combined(with: .opacity))
        }
        if showCallBubble {
            IndicatorBubble(text: "\u{1F4DE}")
                .offset(x: 0, y: -55)
                .transition(.scale.combined(with: .opacity))
        } else if hasMissedCall {
            SmallSpeechBubble(icon: "\u{1F4DE}")
                .offset(x: 30, y: -50)
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
        callMenuItems
    }

    @ViewBuilder
    private var callMenuItems: some View {
        let links = PresenceManager.parseCallLinks(from: friend.facetimeContact)
        if links.count > 1 {
            Menu("Call") {
                ForEach(links, id: \.url) { link in
                    Button(link.label) {
                        if let url = URL(string: link.url) {
                            NSWorkspace.shared.open(url)
                        }
                        Task { await PresenceManager.shared.sendCallRequest(to: friend.userId) }
                    }
                }
            }
        } else if links.count == 1 {
            Button("Call via \(links[0].label)") {
                if let url = URL(string: links[0].url) {
                    NSWorkspace.shared.open(url)
                }
                Task { await PresenceManager.shared.sendCallRequest(to: friend.userId) }
            }
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
        // If the chat window is already open, don't show the bubble indicator
        if notification.userInfo?["chatOpen"] as? Bool == true { return }

        let text = notification.userInfo?["messageText"] as? String
        incomingMessageText = text

        // Show the full speech bubble with message text
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showFullChatBubble = true
            hasUnreadMessage = true
        }

        // After 20 seconds, collapse to the small speech bubble indicator
        DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
            withAnimation(.easeOut(duration: 0.4)) {
                showFullChatBubble = false
            }
        }
    }

    private func handleIncomingCall() {
        // Show call bubble briefly
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showCallBubble = true
            hasMissedCall = true
        }
        // Hide the call bubble after 3s, leave the missed call indicator
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                showCallBubble = false
            }
        }
    }

    private func clearUnread() {
        withAnimation(.easeOut(duration: 0.3)) {
            hasUnreadMessage = false
            showFullChatBubble = false
            incomingMessageText = nil
            hasMissedCall = false
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

// MARK: - Speech Bubble Views

/// Large whimsical speech bubble for incoming messages — cartoon style with tail
private struct SpeechBubbleView: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.custom("Caveat", size: 16).weight(.semibold))
                .foregroundStyle(Color(red: 0.29, green: 0.22, blue: 0.16)) // dark-brown
                .lineLimit(4)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 50, maxWidth: 170)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(red: 1.0, green: 0.91, blue: 0.84), lineWidth: 1.5) // peach border
                )
                .fixedSize(horizontal: false, vertical: true)

            // Speech bubble tail
            BubbleTail()
                .fill(Color.white)
                .frame(width: 14, height: 8)
                .shadow(color: Color.black.opacity(0.08), radius: 1, y: 1)
        }
    }
}

/// Small speech bubble indicator for unread messages or missed calls
private struct SmallSpeechBubble: View {
    var icon: String = "\u{1F4AC}"

    var body: some View {
        VStack(spacing: 0) {
            Text(icon)
                .font(.system(size: 14))
                .padding(5)
                .background(
                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
                )
                .overlay(
                    Circle()
                        .stroke(Color(red: 1.0, green: 0.91, blue: 0.84), lineWidth: 1)
                )
            BubbleTail()
                .fill(Color.white)
                .frame(width: 8, height: 5)
        }
    }
}

/// Emoji indicator bubble (for waves)
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

/// Triangle tail shape for speech bubbles
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - rect.width / 2, y: 0))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height))
        path.addLine(to: CGPoint(x: rect.midX + rect.width / 2, y: 0))
        path.closeSubpath()
        return path
    }
}
