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
}
