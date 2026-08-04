/// Owns the handlers attached by `JSPromise.observe(success:failure:)`.
///
/// Retain this value for as long as callbacks should remain active. Calling
/// `cancel()` or releasing the observation makes both JavaScript handlers inert
/// and releases their Swift closures. Cancellation is idempotent.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
public final class JSPromiseObservation: Sendable {
    private let storage: JSPromiseObservationStorage

    init(
        handle: JSOneshotClosure.ObservationHandle,
        gate: JSPromiseObservationGate
    ) {
        self.storage = JSPromiseObservationStorage(
            handle: handle,
            gate: gate
        )
    }

    /// Prevents either observation callback from being invoked in the future.
    public func cancel() {
        storage.cancel()
    }

    deinit {
        cancel()
    }
}
