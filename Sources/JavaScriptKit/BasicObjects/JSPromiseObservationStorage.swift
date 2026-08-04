import Synchronization

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
final class JSPromiseObservationStorage: Sendable {
    private let handle: Mutex<JSOneshotClosure.ObservationHandle?>
    private let gate: JSPromiseObservationGate

    init(
        handle: JSOneshotClosure.ObservationHandle,
        gate: JSPromiseObservationGate
    ) {
        self.handle = Mutex(handle)
        self.gate = gate
    }

    func cancel() {
        gate.cancel()
        let installedHandle = handle.withLock { handle in
            let installedHandle = handle
            handle = nil
            return installedHandle
        }
        guard let installedHandle else {
            return
        }
        JSOneshotClosure.cancelObservation(installedHandle)
    }
}
