import Foundation
import IOKit

@MainActor
final class ActivityMonitor: ObservableObject {
    static let shared = ActivityMonitor()

    @Published private(set) var state: BuddyState = .active
    @Published var isAvailableToCowork: Bool = false
    @Published var characterType: CharacterType = CharacterType.saved {
        didSet { CharacterType.save(characterType) }
    }

    private var timer: Timer?
    private var debounceWork: DispatchWorkItem?

    // Thresholds in seconds
    var idleThreshold: TimeInterval = 120   // 2 minutes
    var asleepThreshold: TimeInterval = 600 // 10 minutes
    private let debounceInterval: TimeInterval = 5

    private init() {}

    /// Creates a detached instance for SwiftUI previews — does not affect the shared singleton.
    static func preview(state: BuddyState, character: CharacterType = .owl1) -> ActivityMonitor {
        let m = ActivityMonitor()
        m.state = state
        m.characterType = character
        return m
    }

    /// For SwiftUI previews only
    func forceState(_ newState: BuddyState) {
        state = newState
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        debounceWork?.cancel()
    }

    private func poll() {
        let idle = systemIdleTime()
        let newState: BuddyState
        if idle >= asleepThreshold {
            newState = .asleep
        } else if idle >= idleThreshold {
            newState = .idle
        } else {
            newState = .active
        }

        guard newState != state else {
            debounceWork?.cancel()
            debounceWork = nil
            return
        }

        guard debounceWork == nil else { return }

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let currentIdle = self.systemIdleTime()
                let confirmedState: BuddyState
                if currentIdle >= self.asleepThreshold {
                    confirmedState = .asleep
                } else if currentIdle >= self.idleThreshold {
                    confirmedState = .idle
                } else {
                    confirmedState = .active
                }
                self.state = confirmedState
                self.debounceWork = nil
            }
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func systemIdleTime() -> TimeInterval {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator
        ) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var unmanagedDict: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            entry, &unmanagedDict, kCFAllocatorDefault, 0
        ) == KERN_SUCCESS,
              let dict = unmanagedDict?.takeRetainedValue() as? [String: Any],
              let idleNano = dict["HIDIdleTime"] as? Int64 else {
            return 0
        }

        return TimeInterval(idleNano) / 1_000_000_000
    }
}
