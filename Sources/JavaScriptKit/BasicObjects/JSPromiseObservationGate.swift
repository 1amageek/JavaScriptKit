import Synchronization

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
final class JSPromiseObservationGate: Sendable {
    private let isActive = Mutex(true)

    func claimSettlement() -> Bool {
        isActive.withLock { isActive in
            guard isActive else {
                return false
            }
            isActive = false
            return true
        }
    }

    func cancel() {
        isActive.withLock { isActive in
            isActive = false
        }
    }
}
