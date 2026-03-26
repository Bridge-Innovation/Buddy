import SwiftUI
import Foundation

extension Notification.Name {
    /// Triggers the wave animation on the user's own character
    static let buddyIncomingWave = Notification.Name("buddyIncomingWave")
    /// Tells a specific friend avatar to show the wave bubble (userInfo: ["fromUserId": String])
    static let buddyFriendWaved = Notification.Name("buddyFriendWaved")
}

enum BuddyState: String, CaseIterable, Hashable {
    case active = "Active"
    case idle = "Idle"
    case asleep = "Asleep"

    var icon: String {
        switch self {
        case .active: "face.smiling"
        case .idle: "zzz"
        case .asleep: "moon.fill"
        }
    }
}
