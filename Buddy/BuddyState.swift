import SwiftUI
import Foundation

extension Notification.Name {
    /// Triggers the wave animation on the user's own character
    static let buddyIncomingWave = Notification.Name("buddyIncomingWave")
    /// Tells a specific friend avatar to show the wave bubble (userInfo: ["fromUserId": String])
    static let buddyFriendWaved = Notification.Name("buddyFriendWaved")
    /// Incoming chat message (userInfo: ["fromUserId": String])
    static let buddyIncomingMessage = Notification.Name("buddyIncomingMessage")
    /// Open chat window for a friend (userInfo: ["friendId": String])
    static let buddyOpenChat = Notification.Name("buddyOpenChat")
    /// Remote friend is waving at us — play wave animation only (userInfo: ["fromUserId": String])
    static let buddyFriendWaveReceived = Notification.Name("buddyFriendWaveReceived")
    /// Incoming call request (userInfo: ["fromUserId": String, "fromDisplayName": String, "facetimeContact": String])
    static let buddyIncomingCall = Notification.Name("buddyIncomingCall")
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
