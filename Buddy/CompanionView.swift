import SwiftUI

struct CompanionView: View {
    @EnvironmentObject var monitor: ActivityMonitor
    @State private var bounceScale: CGFloat = 1.0
    @State private var waveFrameImage: String?
    @State private var isWaving = false

    private var theme: CharacterTheme { monitor.characterType.theme }
    private var isAvailable: Bool { monitor.isAvailableToCowork && monitor.state == .active }

    var body: some View {
        ZStack {
            // Pulsing green glow behind the character when available
            if isAvailable {
                AvailableGlowView()
            }

            // Wave animation overlay — takes priority over all states
            if let waveImage = waveFrameImage {
                Image(waveImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 192, height: 192)
            } else {
                // State views layered — crossfade via opacity
                ActiveStateView(theme: theme, isAvailable: isAvailable)
                    .opacity(monitor.state == .active ? 1 : 0)

                IdleStateView(theme: theme)
                    .opacity(monitor.state == .idle ? 1 : 0)

                ZStack {
                    AsleepStateView(theme: theme)
                    if monitor.state == .asleep {
                        FloatingZsView()
                    }
                }
                .opacity(monitor.state == .asleep ? 1 : 0)
            }
        }
        .frame(width: 192, height: 192)
        .scaleEffect(bounceScale)
        .animation(.easeInOut(duration: 0.8), value: monitor.state)
        .animation(.easeInOut(duration: 0.5), value: isAvailable)
        .onTapGesture(count: 2) { playWave() }
        .onTapGesture(count: 1) { playBounce() }
        .onReceive(NotificationCenter.default.publisher(for: .buddyIncomingWave)) { _ in
            playWave()
        }
    }

    private func playBounce() {
        guard !isWaving else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) {
            bounceScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                bounceScale = 1.0
            }
        }
    }

    func playWave() {
        let frames = theme.waveFrames
        guard !frames.isEmpty, !isWaving else { return }
        isWaving = true

        Task { @MainActor in
            // low → med → high → med → high → med → low, ~100ms per frame
            for frame in frames {
                waveFrameImage = frame
                try? await Task.sleep(for: .milliseconds(100))
            }
            waveFrameImage = nil
            isWaving = false
        }
    }
}

// MARK: - Active State (alert owl, normal blinking)

// MARK: - Available Glow

struct AvailableGlowView: View {
    @State private var glowOpacity: Double = 0.3

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 160, height: 160)
            .blur(radius: 20)
            .opacity(glowOpacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true)
                ) {
                    glowOpacity = 0.7
                }
            }
    }
}

// MARK: - Active State (alert owl, normal blinking)

struct ActiveStateView: View {
    let theme: CharacterTheme
    let isAvailable: Bool
    @State private var isBreathing = false
    @State private var blinkFrame: String?
    @State private var blinkTimer: Timer?

    private var blinkSequence: BlinkSequence? { theme.blinkFrames[.active] }
    private var displayImage: String? {
        if isAvailable, let availImg = theme.availableImage {
            return blinkFrame ?? availImg
        }
        return blinkFrame ?? blinkSequence?.open
    }

    var body: some View {
        Group {
            if let imageName = displayImage {
                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                PlaceholderBody(theme: theme, state: .active)
            }
        }
        .frame(width: 192, height: 192)
        .scaleEffect(isBreathing ? 1.03 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
            scheduleNextBlink()
        }
        .onDisappear { blinkTimer?.invalidate() }
    }

    private func scheduleNextBlink() {
        let delay = Double.random(in: 3.0...5.0)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task { @MainActor in
                await playBlink()
                scheduleNextBlink()
            }
        }
    }

    private func playBlink() async {
        guard let sequence = blinkSequence else { return }
        // open → half → closed → half → open, ~50ms per frame
        for frame in sequence.frames.dropLast() {
            blinkFrame = frame
            try? await Task.sleep(for: .milliseconds(50))
        }
        blinkFrame = nil
    }
}

// MARK: - Idle State (drowsy owl, slow heavy blinks)

struct IdleStateView: View {
    let theme: CharacterTheme
    @State private var isDrowsyBlinking = false
    @State private var blinkTimer: Timer?

    private var idleConfig: IdleImageConfig? { theme.idleImages }

    private var displayImage: String? {
        guard let config = idleConfig else { return nil }
        return isDrowsyBlinking ? config.closedImage : config.baseImage
    }

    var body: some View {
        Group {
            if let imageName = displayImage {
                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                PlaceholderBody(theme: theme, state: .idle)
            }
        }
        .frame(width: 192, height: 192)
        // Slightly squished — settled and drowsy
        .scaleEffect(x: 1.02, y: 0.98)
        .animation(.easeInOut(duration: 0.3), value: isDrowsyBlinking)
        .onAppear { scheduleDrowsyBlink() }
        .onDisappear { blinkTimer?.invalidate() }
    }

    private func scheduleDrowsyBlink() {
        let delay = Double.random(in: 4.0...5.0)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task { @MainActor in
                await playDrowsyBlink()
                scheduleDrowsyBlink()
            }
        }
    }

    private func playDrowsyBlink() async {
        // half → closed (hold 300ms) → half — heavy eyelids
        isDrowsyBlinking = true
        try? await Task.sleep(for: .milliseconds(300))
        isDrowsyBlinking = false
    }
}

// MARK: - Asleep State (breathing crossfade)

struct AsleepStateView: View {
    let theme: CharacterTheme
    @State private var showInhale = true
    @State private var breathTimer: Timer?

    private var breathing: BreathingConfig? { theme.asleepBreathing }

    var body: some View {
        Group {
            if let config = breathing {
                Image(showInhale ? config.inhaleImage : config.exhaleImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                PlaceholderBody(theme: theme, state: .asleep)
            }
        }
        .frame(width: 192, height: 192)
        .onAppear {
            breathTimer = Timer.scheduledTimer(withTimeInterval: 1.75, repeats: true) { _ in
                Task { @MainActor in showInhale.toggle() }
            }
        }
        .onDisappear {
            breathTimer?.invalidate()
            breathTimer = nil
        }
    }
}

// MARK: - Floating Z's

struct FloatingZsView: View {
    var body: some View {
        ZStack {
            FloatingZ(size: 14, xOffset: 8,  delay: 0)
            FloatingZ(size: 10, xOffset: 18, delay: 1.5)
            FloatingZ(size: 8,  xOffset: 4,  delay: 3.0)
        }
        .frame(width: 120, height: 120, alignment: .top)
    }
}

private struct FloatingZ: View {
    let size: CGFloat
    let xOffset: CGFloat
    let delay: TimeInterval

    @State private var isAnimating = false

    private let zColor = Color(red: 0.55, green: 0.38, blue: 0.20)

    var body: some View {
        Text("z")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(zColor)
            .opacity(isAnimating ? 0 : 0.85)
            .offset(
                x: xOffset,
                y: isAnimating ? -50 : -10
            )
            .onAppear { startLoop() }
    }

    private func startLoop() {
        // Initial delay to stagger the z's
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            animate()
        }
    }

    private func animate() {
        // Reset to start position instantly
        withAnimation(.linear(duration: 0)) {
            isAnimating = false
        }

        // After a tiny beat, drift up and fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(
                .easeOut(duration: 2.0)
            ) {
                isAnimating = true
            }

            // Schedule next z after full cycle
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                animate()
            }
        }
    }
}

// MARK: - Placeholder body (for characters without image assets)

private struct PlaceholderBody: View {
    let theme: CharacterTheme
    let state: BuddyState

    private var pose: Pose { theme.pose(for: state) }

    var body: some View {
        ZStack {
            if let accessory = pose.accessory {
                AccessoryView(style: accessory, bodySize: pose.bodySize)
            }

            Circle()
                .fill(pose.bodyColor.opacity(0.85))
                .frame(width: pose.bodySize, height: pose.bodySize)

            EyeView(style: pose.eyeStyle)
                .offset(y: -pose.bodySize * 0.075)

            MouthView(style: pose.mouthStyle)
                .offset(y: pose.bodySize * 0.175)
        }
    }
}

// MARK: - Eye rendering

private struct EyeView: View {
    let style: EyeStyle

    var body: some View {
        switch style {
        case .open(let size, let pupilSize, let spacing):
            HStack(spacing: spacing) {
                openEye(size: size, pupilSize: pupilSize)
                openEye(size: size, pupilSize: pupilSize)
            }
        case .halfClosed(let size, let spacing):
            HStack(spacing: spacing) {
                halfClosedEye(size: size)
                halfClosedEye(size: size)
            }
        case .closed(let width, let spacing):
            HStack(spacing: spacing) {
                closedEye(width: width)
                closedEye(width: width)
            }
        }
    }

    private func openEye(size: CGFloat, pupilSize: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .fill(Color.black)
                    .frame(width: pupilSize, height: pupilSize)
                    .offset(y: 1)
            )
    }

    private func halfClosedEye(size: CGFloat) -> some View {
        Capsule()
            .fill(Color.white)
            .frame(width: size, height: size * 0.6)
            .overlay(
                Circle()
                    .fill(Color.black)
                    .frame(width: size * 0.45, height: size * 0.45)
                    .offset(y: 1)
            )
    }

    private func closedEye(width: CGFloat) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.7))
            .frame(width: width, height: 3)
    }
}

// MARK: - Mouth rendering

private struct MouthView: View {
    let style: MouthStyle

    var body: some View {
        switch style {
        case .smile(let width, let height):
            Capsule()
                .fill(Color.white)
                .frame(width: width, height: height)
        case .smallO(let diameter):
            Circle()
                .fill(Color.white)
                .frame(width: diameter, height: diameter)
        case .flat(let width):
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: width, height: 3)
        case .hidden:
            EmptyView()
        }
    }
}

// MARK: - Accessory rendering

private struct AccessoryView: View {
    let style: AccessoryStyle
    let bodySize: CGFloat

    var body: some View {
        switch style {
        case .earTufts(let color):
            HStack(spacing: bodySize * 0.45) {
                earTuft(color: color, flipped: false)
                earTuft(color: color, flipped: true)
            }
            .offset(y: -bodySize * 0.45)

        case .pointedEars(let color):
            HStack(spacing: bodySize * 0.5) {
                pointedEar(color: color, flipped: false)
                pointedEar(color: color, flipped: true)
            }
            .offset(y: -bodySize * 0.42)

        case .roundEars(let color):
            HStack(spacing: bodySize * 0.55) {
                Circle()
                    .fill(color)
                    .frame(width: bodySize * 0.3, height: bodySize * 0.3)
                Circle()
                    .fill(color)
                    .frame(width: bodySize * 0.3, height: bodySize * 0.3)
            }
            .offset(y: -bodySize * 0.4)
        }
    }

    private func earTuft(color: Color, flipped: Bool) -> some View {
        Triangle()
            .fill(color)
            .frame(width: 14, height: 18)
            .scaleEffect(x: flipped ? -1 : 1, y: 1)
            .rotationEffect(.degrees(flipped ? 15 : -15))
    }

    private func pointedEar(color: Color, flipped: Bool) -> some View {
        Triangle()
            .fill(color)
            .frame(width: 16, height: 20)
            .scaleEffect(x: flipped ? -1 : 1, y: 1)
            .rotationEffect(.degrees(flipped ? 12 : -12))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

private let desktopGradient = LinearGradient(
    colors: [Color(red: 0.16, green: 0.32, blue: 0.75), Color(red: 0.28, green: 0.11, blue: 0.51)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

#Preview("Owl — Active") {
    CompanionView()
        .environmentObject(ActivityMonitor.preview(state: .active, character: .owl1))
        .frame(width: 200, height: 200)
        .background(desktopGradient)
}

#Preview("Owl — Idle") {
    CompanionView()
        .environmentObject(ActivityMonitor.preview(state: .idle, character: .owl1))
        .frame(width: 200, height: 200)
        .background(desktopGradient)
}

#Preview("Owl — Asleep") {
    CompanionView()
        .environmentObject(ActivityMonitor.preview(state: .asleep, character: .owl1))
        .frame(width: 200, height: 200)
        .background(desktopGradient)
}

#Preview("Fox — Active") {
    CompanionView()
        .environmentObject(ActivityMonitor.preview(state: .active, character: .fox))
        .frame(width: 200, height: 200)
        .background(desktopGradient)
}

#Preview("Hamster — Active") {
    CompanionView()
        .environmentObject(ActivityMonitor.preview(state: .active, character: .hamster))
        .frame(width: 200, height: 200)
        .background(desktopGradient)
}

#Preview("Cat — Idle") {
    CompanionView()
        .environmentObject(ActivityMonitor.preview(state: .idle, character: .cat))
        .frame(width: 200, height: 200)
        .background(desktopGradient)
}
