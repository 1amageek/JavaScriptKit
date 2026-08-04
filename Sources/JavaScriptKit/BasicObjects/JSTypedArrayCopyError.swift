/// A failure while reading bytes from a JavaScript typed array.
public enum JSTypedArrayCopyError: Error, Equatable, Sendable {
    /// The wrapped JavaScript object is not a usable typed array.
    case invalidTypedArray

    /// The typed-array byte length cannot be represented by the bridge ABI.
    case byteLengthOutOfRange

    /// The destination cannot be represented by the bridge ABI.
    case destinationByteCountOutOfRange(capacity: Int)

    /// The destination does not have enough writable bytes.
    case destinationTooSmall(required: Int, capacity: Int)

    /// The JavaScript runtime could not access the requested Wasm memory.
    case memoryAccessFailed

    /// The JavaScript runtime returned an unsupported status code.
    case unexpectedRuntimeStatus(Int32)
}
