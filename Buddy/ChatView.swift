import SwiftUI

struct ChatView: View {
    let friend: FriendStatus
    let myTheme: CharacterTheme
    let friendTheme: CharacterTheme
    @StateObject private var viewModel: ChatViewModel
    @State private var inputText = ""
    @State private var myOwlBounce = false
    @State private var friendOwlBounce = false

    init(friend: FriendStatus, myTheme: CharacterTheme, friendTheme: CharacterTheme) {
        self.friend = friend
        self.myTheme = myTheme
        self.friendTheme = friendTheme
        self._viewModel = StateObject(wrappedValue: ChatViewModel(friendId: friend.userId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — two owls facing each other
            chatHeader
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()
                .background(Color.brown.opacity(0.2))

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.messages) { msg in
                            MessageBubble(message: msg, myUserId: PresenceManager.shared.userId)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.messages.count) { oldCount, newCount in
                    if newCount > oldCount, let last = viewModel.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()
                .background(Color.brown.opacity(0.2))

            // Input
            HStack(spacing: 8) {
                TextField("Say something...", text: $inputText, prompt:
                    Text("Say something...")
                        .foregroundStyle(Color(red: 0.55, green: 0.45, blue: 0.35))
                )
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color(red: 0.3, green: 0.22, blue: 0.12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(red: 0.96, green: 0.93, blue: 0.88))
                    )
                    .onSubmit { send() }

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            inputText.isEmpty
                            ? Color.brown.opacity(0.3)
                            : Color(red: 0.75, green: 0.55, blue: 0.25)
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.98, green: 0.96, blue: 0.92))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onReceive(
            NotificationCenter.default.publisher(for: .buddyIncomingMessage)
                .compactMap { $0.userInfo?["fromUserId"] as? String }
                .filter { $0 == friend.userId }
        ) { _ in
            viewModel.receiveMessages(from: friend.userId)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) {
                friendOwlBounce = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation { friendOwlBounce = false }
            }
        }
    }

    // MARK: - Header with owls

    private var chatHeader: some View {
        HStack {
            // Friend's owl (left)
            miniOwl(theme: friendTheme)
                .scaleEffect(friendOwlBounce ? 1.2 : 1.0)

            VStack(spacing: 1) {
                Text(friend.displayName)
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundStyle(Color(red: 0.4, green: 0.3, blue: 0.2))
            }

            Spacer()

            // My owl (right, flipped to face left)
            miniOwl(theme: myTheme)
                .scaleEffect(x: -1, y: 1)
                .scaleEffect(myOwlBounce ? 1.2 : 1.0)
        }
    }

    private func miniOwl(theme: CharacterTheme) -> some View {
        Group {
            if let blink = theme.blinkFrames[.active] {
                Image(blink.open)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Circle()
                    .fill(Color.brown)
            }
        }
        .frame(width: 36, height: 36)
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        viewModel.send(message: text, to: friend.userId)

        withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) {
            myOwlBounce = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation { myOwlBounce = false }
        }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let myUserId: String?

    private var isMe: Bool { message.fromUserId == myUserId }

    private let myColor = Color(red: 0.92, green: 0.78, blue: 0.50)       // warm amber/honey
    private let friendColor = Color(red: 0.94, green: 0.91, blue: 0.85)   // soft cream
    private let textColor = Color(red: 0.3, green: 0.22, blue: 0.12)      // warm brown

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 40) }

            Text(message.message)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(textColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    BubbleShape(isFromMe: isMe)
                        .fill(isMe ? myColor : friendColor)
                )

            if !isMe { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Speech Bubble Shape

private struct BubbleShape: Shape {
    let isFromMe: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 14
        let tailSize: CGFloat = 6

        var path = Path()

        if isFromMe {
            // Rounded rect with tail on bottom-right
            path.addRoundedRect(
                in: CGRect(x: rect.minX, y: rect.minY,
                           width: rect.width - tailSize, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
            // Little tail
            let tailX = rect.maxX - tailSize
            let tailY = rect.maxY - 8
            path.move(to: CGPoint(x: tailX, y: tailY))
            path.addLine(to: CGPoint(x: tailX + tailSize, y: tailY + 4))
            path.addLine(to: CGPoint(x: tailX, y: tailY + 8))
        } else {
            // Rounded rect with tail on bottom-left
            path.addRoundedRect(
                in: CGRect(x: rect.minX + tailSize, y: rect.minY,
                           width: rect.width - tailSize, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
            // Little tail
            let tailX = rect.minX + tailSize
            let tailY = rect.maxY - 8
            path.move(to: CGPoint(x: tailX, y: tailY))
            path.addLine(to: CGPoint(x: tailX - tailSize, y: tailY + 4))
            path.addLine(to: CGPoint(x: tailX, y: tailY + 8))
        }

        return path
    }
}

// MARK: - View Model

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    let friendId: String

    init(friendId: String) {
        self.friendId = friendId
        // Grab any already-pending messages
        receiveMessages(from: friendId)
    }

    func send(message: String, to friendId: String) {
        guard let myId = PresenceManager.shared.userId else { return }

        // Add locally immediately
        let local = ChatMessage(
            id: UUID().uuidString,
            fromUserId: myId,
            fromDisplayName: "Me",
            toUserId: friendId,
            message: message,
            timestamp: Date().timeIntervalSince1970 * 1000
        )
        messages.append(local)

        Task {
            await PresenceManager.shared.sendMessage(to: friendId, message: message)
        }
    }

    func receiveMessages(from friendId: String) {
        let incoming = PresenceManager.shared.consumeMessages(from: friendId)
        messages.append(contentsOf: incoming)
    }
}
