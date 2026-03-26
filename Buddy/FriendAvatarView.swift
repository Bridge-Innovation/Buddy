import SwiftUI

struct FriendAvatarView: View {
    let friend: FriendStatus
    let theme: CharacterTheme
    @State private var waveFrameImage: String?
    @State private var isWaving = false
    @State private var showWaveBubble = false

    private var isAvailable: Bool { friend.isAvailable && friend.state == .active }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Glow when available
                if isAvailable {
                    AvailableGlowView()
                }

                // Wave animation overlay
                if let waveImage = waveFrameImage {
                    Image(waveImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)
                } else {
                    // State-based character
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

                // Wave received indicator
                if showWaveBubble {
                    WaveBubble()
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 140, height: 140)
            .scaleEffect(0.75)
            .animation(.easeInOut(duration: 0.8), value: friend.state)
            .animation(.easeInOut(duration: 0.5), value: isAvailable)
            .onTapGesture(count: 2) { sendWave() }
            .onTapGesture(count: 1) { }

            Text(friend.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(1)
                .frame(maxWidth: 100)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .buddyFriendWaved)
                .compactMap { $0.userInfo?["fromUserId"] as? String }
                .filter { $0 == friend.userId }
        ) { _ in
            showWaveIndicator()
        }
    }

    private func sendWave() {
        guard !isWaving else { return }
        isWaving = true

        Task { @MainActor in
            await PresenceManager.shared.sendWave(to: friend.userId)

            // Play wave animation locally
            let frames = theme.waveFrames
            if !frames.isEmpty {
                for frame in frames {
                    waveFrameImage = frame
                    try? await Task.sleep(for: .milliseconds(100))
                }
                waveFrameImage = nil
            }
            isWaving = false
        }
    }

    func showWaveIndicator() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showWaveBubble = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                showWaveBubble = false
            }
        }
    }
}

// MARK: - Wave Bubble

private struct WaveBubble: View {
    var body: some View {
        Text("\u{1F44B}")
            .font(.system(size: 24))
            .padding(6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(radius: 2)
            )
            .offset(x: 35, y: -45)
    }
}
