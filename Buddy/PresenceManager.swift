import Foundation

// MARK: - API Models

struct FriendStatus: Codable, Identifiable {
    let userId: String
    let displayName: String
    let characterType: String
    let activityState: String
    let isAvailable: Bool
    let lastSeen: Double

    var id: String { userId }

    var state: BuddyState {
        BuddyState(rawValue: activityState.capitalized) ?? .active
    }
}

struct BuddyEvent: Codable, Identifiable {
    let id: String
    let fromUserId: String
    let fromDisplayName: String
    let toUserId: String
    let eventType: String
    let timestamp: Double
}

// MARK: - PresenceManager

@MainActor
final class PresenceManager: ObservableObject {
    static let shared = PresenceManager()

    @Published private(set) var userId: String?
    @Published private(set) var friendCode: String?
    @Published private(set) var friends: [FriendStatus] = []
    @Published private(set) var pendingEvents: [BuddyEvent] = []

    private let baseURL: URL
    private var statusTimer: Timer?
    private var pollTimer: Timer?

    private static let userIdKey = "BuddyUserId"
    private static let friendCodeKey = "BuddyFriendCode"

    private init() {
        // Configurable API base URL
        let urlString = UserDefaults.standard.string(forKey: "BuddyAPIBaseURL")
            ?? "https://buddy-presence.sarahgilmore.workers.dev"
        self.baseURL = URL(string: urlString)!

        // Restore saved credentials
        self.userId = UserDefaults.standard.string(forKey: Self.userIdKey)
        self.friendCode = UserDefaults.standard.string(forKey: Self.friendCodeKey)
    }

    // MARK: - Lifecycle

    func start() {
        Task {
            if userId == nil {
                await register()
            }

            startStatusUpdates()
            startPolling()
        }
    }

    func stop() {
        statusTimer?.invalidate()
        statusTimer = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Registration

    private func register() async {
        struct RegisterResponse: Codable {
            let userId: String
            let friendCode: String
            let displayName: String
        }

        guard let response: RegisterResponse = await post("/register", body: [
            "displayName": "Buddy User",
        ]) else { return }

        userId = response.userId
        friendCode = response.friendCode
        UserDefaults.standard.set(response.userId, forKey: Self.userIdKey)
        UserDefaults.standard.set(response.friendCode, forKey: Self.friendCodeKey)
    }

    // MARK: - Status updates (every 30s)

    private func startStatusUpdates() {
        sendStatus()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendStatus() }
        }
    }

    private struct StatusBody: Encodable {
        let userId: String
        let activityState: String
        let isAvailable: Bool
        let characterType: String
    }

    private func sendStatus() {
        guard let userId else { return }
        let monitor = ActivityMonitor.shared

        Task {
            let _: EmptyResponse? = await post("/status", body: StatusBody(
                userId: userId,
                activityState: monitor.state.rawValue.lowercased(),
                isAvailable: monitor.isAvailableToCowork,
                characterType: monitor.characterType.rawValue
            ))
        }
    }

    // MARK: - Polling (every 5s)

    private func startPolling() {
        pollFriendsAndEvents()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollFriendsAndEvents() }
        }
    }

    private func pollFriendsAndEvents() {
        guard let userId else { return }

        Task {
            async let friendsResult = get("/friends?userId=\(userId)", as: FriendsResponse.self)
            async let eventsResult = get("/events?userId=\(userId)", as: EventsResponse.self)

            if let fr = await friendsResult {
                friends = fr.friends
            }
            if let ev = await eventsResult {
                if !ev.events.isEmpty {
                    pendingEvents.append(contentsOf: ev.events)
                }
            }
        }
    }

    // MARK: - Public actions

    func addFriend(code: String) async -> FriendStatus? {
        guard let userId else { return nil }

        struct AddResponse: Codable {
            let ok: Bool
            let friend: FriendStatus?
        }

        let response: AddResponse? = await post("/friends/add", body: [
            "userId": userId,
            "friendCode": code.uppercased(),
        ])

        if response?.ok == true {
            pollFriendsAndEvents()
        }
        return response?.friend
    }

    func removeFriend(friendId: String) async {
        guard let userId else { return }

        let _: EmptyResponse? = await post("/friends/remove", body: [
            "userId": userId,
            "friendId": friendId,
        ])
        friends.removeAll { $0.userId == friendId }
    }

    func sendWave(to friendId: String) async {
        guard let userId else { return }

        let _: EmptyResponse? = await post("/events/send", body: [
            "fromUserId": userId,
            "toUserId": friendId,
            "eventType": "wave",
        ])
    }

    func consumeEvent(_ event: BuddyEvent) {
        pendingEvents.removeAll { $0.id == event.id }
    }

    // MARK: - Networking

    private func post<T: Codable, B: Encodable>(_ path: String, body: B) async -> T? {
        guard let url = URL(string: path, relativeTo: baseURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("[Buddy] POST \(path) failed: \(error)")
            return nil
        }
    }

    private func get<T: Codable>(_ path: String, as type: T.Type) async -> T? {
        guard let url = URL(string: path, relativeTo: baseURL) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("[Buddy] GET \(path) failed: \(error)")
            return nil
        }
    }
}

// MARK: - Response types

private struct FriendsResponse: Codable {
    let friends: [FriendStatus]
}

private struct EventsResponse: Codable {
    let events: [BuddyEvent]
}

private struct EmptyResponse: Codable {
    let ok: Bool?
    let error: String?
}
