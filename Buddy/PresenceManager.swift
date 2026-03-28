import Foundation

// MARK: - Call Links

struct CallLink: Codable {
    let label: String
    let url: String
}

// MARK: - API Models

struct FriendStatus: Codable, Identifiable {
    let userId: String
    let displayName: String
    let characterType: String
    let activityState: String
    let isAvailable: Bool
    let lastSeen: Double
    let facetimeContact: String?

    var id: String { userId }

    var state: BuddyState {
        BuddyState(rawValue: activityState.capitalized) ?? .active
    }

    var hasFacetime: Bool {
        guard let contact = facetimeContact else { return false }
        return !contact.isEmpty
    }
}

struct ChatMessage: Codable, Identifiable {
    let id: String
    let fromUserId: String
    let fromDisplayName: String
    let toUserId: String
    let message: String
    let timestamp: Double
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
    @Published private(set) var incomingMessages: [ChatMessage] = []
    @Published var displayName: String {
        didSet {
            AppSettings.defaults.set(displayName, forKey: Self.displayNameKey)
            syncProfile()
        }
    }

    @Published var facetimeContact: String {
        didSet {
            AppSettings.defaults.set(facetimeContact, forKey: Self.facetimeContactKey)
            syncProfile()
        }
    }

    private let baseURL: URL
    private var statusTimer: Timer?
    private var eventTimer: Timer?

    // SSE state
    private var sseTask: Task<Void, Never>?
    private var sseRetryCount: Int = 0
    private let sseMaxRetryDelay: TimeInterval = 60

    private static let userIdKey = "BuddyUserId"
    private static let friendCodeKey = "BuddyFriendCode"
    private static let displayNameKey = "BuddyDisplayName"
    private static let facetimeContactKey = "BuddyFacetimeContact"

    private init() {
        // Configurable API base URL
        let urlString = AppSettings.defaults.string(forKey: "BuddyAPIBaseURL")
            ?? "https://buddy-presence.sarahgilmore.workers.dev"
        self.baseURL = URL(string: urlString)!

        // Restore saved credentials
        self.userId = AppSettings.defaults.string(forKey: Self.userIdKey)
        self.friendCode = AppSettings.defaults.string(forKey: Self.friendCodeKey)
        self.displayName = AppSettings.defaults.string(forKey: Self.displayNameKey) ?? ""
        self.facetimeContact = AppSettings.defaults.string(forKey: Self.facetimeContactKey) ?? ""
    }

    // MARK: - Lifecycle

    func start() {
        Task {
            if userId == nil {
                await register()
            }

            startStatusUpdates()
            startPolling()
            connectSSE()
        }
    }

    func stop() {
        statusTimer?.invalidate()
        statusTimer = nil
        eventTimer?.invalidate()
        eventTimer = nil
        sseTask?.cancel()
        sseTask = nil
    }

    // MARK: - Registration

    private func register() async {
        struct RegisterResponse: Codable {
            let userId: String
            let friendCode: String
            let displayName: String
        }

        let name = displayName.isEmpty ? "Buddy User" : displayName
        guard let response: RegisterResponse = await post("/register", body: [
            "displayName": name,
        ]) else { return }

        userId = response.userId
        friendCode = response.friendCode
        AppSettings.defaults.set(response.userId, forKey: Self.userIdKey)
        AppSettings.defaults.set(response.friendCode, forKey: Self.friendCodeKey)
        // Store the name the server accepted
        if displayName.isEmpty {
            displayName = response.displayName
        }
    }

    // MARK: - Status + friends heartbeat (every 60s)

    private func startStatusUpdates() {
        sendStatus()
        pollFriends()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendStatus()
                self?.pollFriends()
            }
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

    // MARK: - Event polling (every 10s — SSE is the fast path, polling is the safety net)

    private func startPolling() {
        pollEvents()
        eventTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollEvents() }
        }
    }

    private func pollFriends() {
        guard let userId else { return }

        Task {
            if let fr = await get("/friends?userId=\(userId)", as: FriendsResponse.self) {
                friends = fr.friends
                if !fr.friends.isEmpty {
                    print("[Buddy] Friends online: \(fr.friends.map { "\($0.displayName) (\($0.userId.prefix(8))...)" }.joined(separator: ", "))")
                }
            }
        }
    }

    func pollEvents() {
        guard let userId else { return }

        Task {
            async let eventsResult = get("/events?userId=\(userId)", as: EventsResponse.self)
            async let messagesResult = get("/messages?userId=\(userId)", as: MessagesResponse.self)

            if let ev = await eventsResult {
                if !ev.events.isEmpty {
                    print("[Buddy] Received \(ev.events.count) event(s): \(ev.events.map { "\($0.eventType) from \($0.fromDisplayName)" }.joined(separator: ", "))")
                    pendingEvents.append(contentsOf: ev.events)
                }
            }
            if let msgs = await messagesResult {
                if !msgs.messages.isEmpty {
                    incomingMessages.append(contentsOf: msgs.messages)
                }
            }
        }
    }

    // MARK: - SSE Connection

    private func connectSSE() {
        sseTask?.cancel()
        sseTask = Task { [weak self] in
            guard let self else { return }
            await self.runSSELoop()
        }
    }

    private func runSSELoop() async {
        while !Task.isCancelled {
            guard let userId = await MainActor.run(body: { self.userId }) else {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }

            guard let streamURL = URL(string: "/stream?userId=\(userId)", relativeTo: baseURL) else {
                return
            }

            print("[Buddy] SSE connecting to \(streamURL)")

            var request = URLRequest(url: streamURL)
            request.timeoutInterval = .infinity
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("[Buddy] SSE bad status, retrying...")
                    await sseBackoff()
                    continue
                }

                // Connected successfully — reset retry count
                await MainActor.run { self.sseRetryCount = 0 }
                print("[Buddy] SSE connected")

                for try await line in bytes.lines {
                    if Task.isCancelled { break }

                    guard line.hasPrefix("data: ") else { continue }
                    let jsonStr = String(line.dropFirst(6))

                    guard let data = jsonStr.data(using: .utf8) else { continue }

                    await self.handleSSEData(data)
                }

                print("[Buddy] SSE stream ended")
            } catch {
                if Task.isCancelled { return }
                print("[Buddy] SSE error: \(error.localizedDescription)")
            }

            await sseBackoff()
        }
    }

    @MainActor
    private func handleSSEData(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let payloadObj = json["payload"] else {
            return
        }

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payloadObj) else {
            return
        }

        let decoder = JSONDecoder()

        switch type {
        case "event":
            if let event = try? decoder.decode(BuddyEvent.self, from: payloadData) {
                // Deduplicate — don't add if already present
                if !pendingEvents.contains(where: { $0.id == event.id }) {
                    print("[Buddy] SSE event: \(event.eventType) from \(event.fromDisplayName)")
                    pendingEvents.append(event)
                }
            }
        case "message":
            if let msg = try? decoder.decode(ChatMessage.self, from: payloadData) {
                if !incomingMessages.contains(where: { $0.id == msg.id }) {
                    print("[Buddy] SSE message from \(msg.fromDisplayName)")
                    incomingMessages.append(msg)
                }
            }
        default:
            break
        }
    }

    private func sseBackoff() async {
        let retryCount = await MainActor.run {
            self.sseRetryCount += 1
            return self.sseRetryCount
        }
        // Exponential backoff: 1s, 2s, 4s, 8s, ... capped at 60s
        let delay = min(pow(2.0, Double(retryCount - 1)), sseMaxRetryDelay)
        print("[Buddy] SSE reconnecting in \(delay)s (attempt \(retryCount))")
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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
            pollFriends()
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
        pollEvents()
    }

    func sendCallRequest(to friendId: String) async {
        guard let userId else { return }

        let _: EmptyResponse? = await post("/events/send", body: [
            "fromUserId": userId,
            "toUserId": friendId,
            "eventType": "call",
        ])
        pollEvents()
    }

    func consumeEvent(_ event: BuddyEvent) {
        pendingEvents.removeAll { $0.id == event.id }
    }

    func sendMessage(to friendId: String, message: String) async {
        guard let userId else { return }

        let _: EmptyResponse? = await post("/messages/send", body: [
            "fromUserId": userId,
            "toUserId": friendId,
            "message": message,
        ])
        pollEvents()
    }

    func consumeMessages(from friendId: String) -> [ChatMessage] {
        let msgs = incomingMessages.filter { $0.fromUserId == friendId }
        incomingMessages.removeAll { $0.fromUserId == friendId }
        return msgs
    }

    private func syncProfile() {
        guard let userId else { return }
        Task {
            let _: EmptyResponse? = await post("/profile/update", body: [
                "userId": userId,
                "displayName": displayName,
                "facetimeContact": facetimeContact,
            ])
        }
    }

    // MARK: - Call link helpers

    static func parseCallLinks(from contactString: String?) -> [CallLink] {
        guard let str = contactString, !str.isEmpty else { return [] }
        // Try JSON array format first
        if str.hasPrefix("["), let data = str.data(using: .utf8),
           let links = try? JSONDecoder().decode([CallLink].self, from: data) {
            return links
        }
        // Legacy: single string — auto-migrate
        if str.contains("@") || str.first?.isNumber == true || str.hasPrefix("+") {
            return [CallLink(label: "FaceTime", url: "facetime://\(str)")]
        }
        if str.hasPrefix("https://wa.me") {
            return [CallLink(label: "WhatsApp", url: str)]
        }
        return [CallLink(label: "Call", url: str)]
    }

    static func serializeCallLinks(_ links: [CallLink]) -> String {
        guard let data = try? JSONEncoder().encode(links) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
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

private struct MessagesResponse: Codable {
    let messages: [ChatMessage]
}

private struct EmptyResponse: Codable {
    let ok: Bool?
    let error: String?
}
