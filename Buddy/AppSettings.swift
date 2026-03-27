import Foundation

/// Centralized UserDefaults access. When launched with `--test-user-2`,
/// uses a separate suite so two instances can run as different users.
enum AppSettings {
    static let defaults: UserDefaults = {
        if CommandLine.arguments.contains("--test-user-2") {
            return UserDefaults(suiteName: "com.sarahgilmore.buddy.testuser2")!
        }
        return UserDefaults.standard
    }()

    static var isTestUser2: Bool {
        CommandLine.arguments.contains("--test-user-2")
    }

    // MARK: - Owl Size

    private static let owlSizeKey = "BuddyOwlSize"

    /// Owl display scale: 0 = small (0.75x), 1 = medium (1.0x), 2 = large (1.35x)
    static var owlSize: Int {
        get { defaults.object(forKey: owlSizeKey) as? Int ?? 1 }
        set { defaults.set(newValue, forKey: owlSizeKey) }
    }

    static var owlScale: CGFloat {
        switch owlSize {
        case 0: return 0.75
        case 2: return 1.35
        default: return 1.0
        }
    }
}
