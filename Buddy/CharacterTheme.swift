import SwiftUI

// MARK: - Character catalog

enum CharacterType: String, CaseIterable, Identifiable {
    case owl1
    case owl2
    case hamster
    case fox
    case cat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .owl1: "Owl 1"
        case .owl2: "Owl 2"
        case .hamster: "Hamster"
        case .fox: "Fox"
        case .cat: "Cat"
        }
    }

    var theme: CharacterTheme {
        switch self {
        case .owl1:    return .owl(suffix: "")
        case .owl2:    return .owl(suffix: "2")
        case .hamster: return .hamster
        case .fox:     return .fox
        case .cat:     return .cat
        }
    }

    /// Resolve a character type from the server's characterType string
    static func from(serverValue: String) -> CharacterType {
        CharacterType(rawValue: serverValue) ?? .owl1
    }

    private static let userDefaultsKey = "BuddyCharacterType"

    /// Load the user's saved selection
    static var saved: CharacterType {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              let type = CharacterType(rawValue: raw) else {
            return .owl1
        }
        return type
    }

    /// Save the user's selection
    static func save(_ type: CharacterType) {
        UserDefaults.standard.set(type.rawValue, forKey: userDefaultsKey)
    }
}

// MARK: - What every character must provide

struct CharacterTheme {
    /// Visual for each activity state
    let poses: [BuddyState: Pose]
    /// Eyes-closed variant of the active pose (used for placeholder blink)
    let blink: Pose
    /// Image-based blink frames per state (open → half → closed → half → open)
    /// If provided for a state, these are used instead of the placeholder Pose swap.
    var blinkFrames: [BuddyState: BlinkSequence] = [:]
    /// Image-based idle/drowsy config (half-closed + closed frames for slow blink)
    var idleImages: IdleImageConfig? = nil
    /// Image-based asleep breathing config (two frames for crossfade)
    var asleepBreathing: BreathingConfig? = nil
    /// Image frames for the wave animation (triggered on demand)
    var waveFrames: [String] = []
    /// Image to use when "available to cowork" — defaults to active open if nil
    var availableImage: String? = nil
    /// Entrance animation style (for future use)
    var entranceAnimation: AnimationStyle = .fadeIn
    /// Exit animation style (for future use)
    var exitAnimation: AnimationStyle = .fadeOut

    func pose(for state: BuddyState) -> Pose {
        poses[state] ?? poses[.active]!
    }
}

/// A sequence of image asset names for a multi-frame blink animation.
struct BlinkSequence {
    /// The default open-eyes image (shown most of the time)
    let open: String
    /// Half-closed transitional frame
    let half: String
    /// Fully closed frame
    let closed: String

    /// The full blink sequence: open → half → closed → half → open
    var frames: [String] { [open, half, closed, half, open] }
}

/// Image config for the idle/drowsy state
struct IdleImageConfig {
    /// Base image — half-closed eyes (shown most of the time)
    let baseImage: String
    /// Fully closed eyes (for drowsy blink)
    let closedImage: String
}

/// Image config for the asleep breathing animation
struct BreathingConfig {
    /// Inhale frame (slightly expanded)
    let inhaleImage: String
    /// Exhale frame (slightly contracted)
    let exhaleImage: String
}

// MARK: - A single character pose

struct Pose {
    let bodyColor: Color
    let bodySize: CGFloat
    let eyeStyle: EyeStyle
    let mouthStyle: MouthStyle
    /// Optional accessory drawn on top (e.g. ear tufts, tail)
    var accessory: AccessoryStyle? = nil
}

enum EyeStyle {
    /// Round eyes with pupils
    case open(size: CGFloat, pupilSize: CGFloat, spacing: CGFloat)
    /// Half-closed / droopy
    case halfClosed(size: CGFloat, spacing: CGFloat)
    /// Fully shut (line)
    case closed(width: CGFloat, spacing: CGFloat)
}

enum MouthStyle {
    case smile(width: CGFloat, height: CGFloat)
    case smallO(diameter: CGFloat)
    case flat(width: CGFloat)
    case hidden
}

enum AccessoryStyle {
    /// Two triangular ear tufts on top
    case earTufts(color: Color)
    /// Pointed ears
    case pointedEars(color: Color)
    /// Round ears
    case roundEars(color: Color)
}

enum AnimationStyle {
    case fadeIn, fadeOut
    case slideUp, slideDown
    case bounce
}

// MARK: - Built-in themes

extension CharacterTheme {
    /// Creates an owl theme with the given image suffix (e.g. "" for owl1, "2" for owl2)
    static func owl(suffix: String) -> CharacterTheme {
        let s = suffix
        return CharacterTheme(
            poses: [
                .active: Pose(
                    bodyColor: .brown,
                    bodySize: 80,
                    eyeStyle: .open(size: 18, pupilSize: 10, spacing: 20),
                    mouthStyle: .smile(width: 12, height: 8),
                    accessory: .earTufts(color: .brown)
                ),
                .idle: Pose(
                    bodyColor: Color.brown.opacity(0.7),
                    bodySize: 80,
                    eyeStyle: .halfClosed(size: 16, spacing: 20),
                    mouthStyle: .smallO(diameter: 8),
                    accessory: .earTufts(color: .brown)
                ),
                .asleep: Pose(
                    bodyColor: Color(red: 0.35, green: 0.25, blue: 0.15),
                    bodySize: 76,
                    eyeStyle: .closed(width: 14, spacing: 20),
                    mouthStyle: .flat(width: 14),
                    accessory: .earTufts(color: .brown)
                ),
            ],
            blink: Pose(
                bodyColor: .brown,
                bodySize: 80,
                eyeStyle: .closed(width: 14, spacing: 20),
                mouthStyle: .smile(width: 12, height: 8),
                accessory: .earTufts(color: .brown)
            ),
            blinkFrames: [
                .active: BlinkSequence(
                    open: "owl_active_open\(s)",
                    half: "owl_active_half\(s)",
                    closed: "owl_active_closed\(s)"
                ),
            ],
            idleImages: IdleImageConfig(
                baseImage: "owl_active_half\(s)",
                closedImage: "owl_active_closed\(s)"
            ),
            asleepBreathing: BreathingConfig(
                inhaleImage: "owl_asleep_in\(s)",
                exhaleImage: "owl_asleep_out\(s)"
            ),
            waveFrames: [
                "owl_wave_low\(s)", "owl_wave_med\(s)", "owl_wave_high\(s)",
                "owl_wave_med\(s)", "owl_wave_high\(s)", "owl_wave_med\(s)", "owl_wave_low\(s)",
            ],
            availableImage: "owl_active_open\(s)"
        )
    }

    static let hamster = CharacterTheme(
        poses: [
            .active: Pose(
                bodyColor: Color(red: 1.0, green: 0.85, blue: 0.55),
                bodySize: 80,
                eyeStyle: .open(size: 14, pupilSize: 8, spacing: 22),
                mouthStyle: .smile(width: 16, height: 5),
                accessory: .roundEars(color: Color(red: 1.0, green: 0.7, blue: 0.7))
            ),
            .idle: Pose(
                bodyColor: Color(red: 0.95, green: 0.80, blue: 0.50),
                bodySize: 80,
                eyeStyle: .halfClosed(size: 12, spacing: 22),
                mouthStyle: .smallO(diameter: 7),
                accessory: .roundEars(color: Color(red: 1.0, green: 0.7, blue: 0.7))
            ),
            .asleep: Pose(
                bodyColor: Color(red: 0.85, green: 0.72, blue: 0.45),
                bodySize: 76,
                eyeStyle: .closed(width: 12, spacing: 22),
                mouthStyle: .hidden,
                accessory: .roundEars(color: Color(red: 1.0, green: 0.7, blue: 0.7))
            ),
        ],
        blink: Pose(
            bodyColor: Color(red: 1.0, green: 0.85, blue: 0.55),
            bodySize: 80,
            eyeStyle: .closed(width: 12, spacing: 22),
            mouthStyle: .smile(width: 16, height: 5),
            accessory: .roundEars(color: Color(red: 1.0, green: 0.7, blue: 0.7))
        )
    )

    static let fox = CharacterTheme(
        poses: [
            .active: Pose(
                bodyColor: Color.orange,
                bodySize: 80,
                eyeStyle: .open(size: 14, pupilSize: 7, spacing: 18),
                mouthStyle: .smile(width: 14, height: 5),
                accessory: .pointedEars(color: .orange)
            ),
            .idle: Pose(
                bodyColor: Color.orange.opacity(0.7),
                bodySize: 80,
                eyeStyle: .halfClosed(size: 12, spacing: 18),
                mouthStyle: .smallO(diameter: 6),
                accessory: .pointedEars(color: .orange)
            ),
            .asleep: Pose(
                bodyColor: Color(red: 0.8, green: 0.45, blue: 0.1),
                bodySize: 76,
                eyeStyle: .closed(width: 12, spacing: 18),
                mouthStyle: .flat(width: 12),
                accessory: .pointedEars(color: .orange)
            ),
        ],
        blink: Pose(
            bodyColor: .orange,
            bodySize: 80,
            eyeStyle: .closed(width: 12, spacing: 18),
            mouthStyle: .smile(width: 14, height: 5),
            accessory: .pointedEars(color: .orange)
        )
    )

    static let cat = CharacterTheme(
        poses: [
            .active: Pose(
                bodyColor: Color(red: 0.35, green: 0.35, blue: 0.4),
                bodySize: 80,
                eyeStyle: .open(size: 16, pupilSize: 9, spacing: 18),
                mouthStyle: .smile(width: 10, height: 4),
                accessory: .pointedEars(color: Color(red: 0.35, green: 0.35, blue: 0.4))
            ),
            .idle: Pose(
                bodyColor: Color(red: 0.3, green: 0.3, blue: 0.35),
                bodySize: 80,
                eyeStyle: .halfClosed(size: 14, spacing: 18),
                mouthStyle: .hidden,
                accessory: .pointedEars(color: Color(red: 0.3, green: 0.3, blue: 0.35))
            ),
            .asleep: Pose(
                bodyColor: Color(red: 0.25, green: 0.25, blue: 0.3),
                bodySize: 76,
                eyeStyle: .closed(width: 14, spacing: 18),
                mouthStyle: .flat(width: 10),
                accessory: .pointedEars(color: Color(red: 0.25, green: 0.25, blue: 0.3))
            ),
        ],
        blink: Pose(
            bodyColor: Color(red: 0.35, green: 0.35, blue: 0.4),
            bodySize: 80,
            eyeStyle: .closed(width: 14, spacing: 18),
            mouthStyle: .smile(width: 10, height: 4),
            accessory: .pointedEars(color: Color(red: 0.35, green: 0.35, blue: 0.4))
        )
    )
}
