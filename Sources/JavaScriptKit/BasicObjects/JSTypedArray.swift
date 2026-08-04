//
//  Created by Manuel Burghard. Licensed unter MIT.
//
import _CJavaScriptKit

private enum JSTypedArrayCopyStatus: Int32 {
    case success = 0
    case invalidTypedArray = 1
    case byteLengthOutOfRange = 2
    case destinationTooSmall = 3
    case memoryAccessFailed = 4
}

/// A protocol that allows a Swift numeric type to be mapped to the JavaScript TypedArray that holds integers of its type
public protocol TypedArrayElement {
    associatedtype Element: ConvertibleToJSValue, ConstructibleFromJSValue = Self
    /// The constructor function for the TypedArray class for this particular kind of number
    static var typedArrayClass: JSObject { get }
}

/// A wrapper around all [JavaScript `TypedArray`
/// classes](https://developer.mozilla.org/docs/Web/JavaScript/Reference/Global_Objects/TypedArray)
/// that exposes their properties in a type-safe way.
public final class JSTypedArray<Traits>: JSBridgedClass, ExpressibleByArrayLiteral where Traits: TypedArrayElement {
    public typealias Element = Traits.Element
    public class var constructor: JSObject? { Traits.typedArrayClass }
    public var jsObject: JSObject

    public subscript(_ index: Int) -> Element {
        get {
            return Element.construct(from: jsObject[index])!
        }
        set {
            jsObject[index] = newValue.jsValue
        }
    }

    /// Initialize a new instance of TypedArray in JavaScript environment with given length.
    ///  All the elements will be initialized to zero.
    ///
    /// - Parameter length: The number of elements that will be allocated.
    public init(length: Int) {
        jsObject = Self.constructor!.new(length)
    }

    public required init(unsafelyWrapping jsObject: JSObject) {
        self.jsObject = jsObject
    }

    public required convenience init(arrayLiteral elements: Element...) {
        self.init(elements)
    }

    /// Initialize a new instance of TypedArray in JavaScript environment with given elements.
    ///
    /// - Parameter array: The array that will be copied to create a new instance of TypedArray
    public convenience init(_ array: [Element]) {
        let object = array.withUnsafeBufferPointer { buffer in
            Self.createTypedArray(from: buffer)
        }
        self.init(unsafelyWrapping: object)
    }

    /// Convenience initializer for `Sequence`.
    public convenience init<S: Sequence>(_ sequence: S) where S.Element == Element {
        self.init(Array(sequence))
    }

    /// Initialize a new instance of TypedArray in JavaScript environment with given buffer contents.
    ///
    /// - Parameter buffer: The buffer that will be copied to create a new instance of TypedArray
    public convenience init(buffer: UnsafeBufferPointer<Element>) {
        self.init(unsafelyWrapping: Self.createTypedArray(from: buffer))
    }

    private static func createTypedArray(from buffer: UnsafeBufferPointer<Element>) -> JSObject {
        // Retain the constructor function to avoid it being released before calling `swjs_create_typed_array`
        let jsArrayRef = withExtendedLifetime(Self.constructor!) { ctor in
            swjs_create_typed_array(ctor.id, buffer.baseAddress, Int32(buffer.count))
        }
        return JSObject(id: jsArrayRef)
    }

    /// Length (in bytes) of the typed array.
    /// The value is established when a TypedArray is constructed and cannot be changed.
    /// This is the intrinsic byte length of the view, not the complete backing
    /// `ArrayBuffer` length.
    public var lengthInBytes: Int {
        do {
            return try validatedByteLength()
        } catch {
            preconditionFailure(
                "The wrapped JavaScript object is not a usable typed array: \(error)"
            )
        }
    }

    /// Length (in elements) of the typed array.
    public var length: Int {
        let byteLength = lengthInBytes
        let elementStride = MemoryLayout<Element>.stride
        precondition(
            byteLength.isMultiple(of: elementStride),
            "Typed-array byte length is not aligned to its element stride"
        )
        return byteLength / elementStride
    }

    /// Returns the intrinsic byte length of the typed array.
    ///
    /// Unlike JavaScript property access, this operation cannot be changed by an
    /// own property, subclass override, or Proxy. Invalid and detached views are
    /// reported as typed failures.
    public func validatedByteLength() throws(JSTypedArrayCopyError) -> Int {
        var byteLength: UInt32 = 0
        let status = swjs_get_typed_array_byte_length(
            jsObject.id,
            &byteLength
        )
        switch JSTypedArrayCopyStatus(rawValue: status) {
        case .success:
            return Int(byteLength)
        case .invalidTypedArray:
            throw .invalidTypedArray
        case .byteLengthOutOfRange:
            throw .byteLengthOutOfRange
        case .destinationTooSmall, .memoryAccessFailed:
            throw .unexpectedRuntimeStatus(status)
        case nil:
            throw .unexpectedRuntimeStatus(status)
        }
    }

    /// Copies the exact typed-array byte view into a bounded destination.
    ///
    /// The JavaScript object owns the source storage for the duration of this
    /// synchronous call. The destination is borrowed only for the call and its
    /// pointer never escapes into JavaScript. The runtime validates the current
    /// intrinsic byte length before writing any byte.
    public func copyBytes(
        to destination: UnsafeMutableRawBufferPointer
    ) throws(JSTypedArrayCopyError) {
        guard let capacity = UInt32(exactly: destination.count) else {
            throw .destinationByteCountOutOfRange(
                capacity: destination.count
            )
        }
        var byteLength: UInt32 = 0
        let status = swjs_copy_typed_array_bytes(
            jsObject.id,
            destination.baseAddress?.assumingMemoryBound(to: UInt8.self),
            capacity,
            &byteLength
        )
        switch JSTypedArrayCopyStatus(rawValue: status) {
        case .success:
            return
        case .invalidTypedArray:
            throw .invalidTypedArray
        case .byteLengthOutOfRange:
            throw .byteLengthOutOfRange
        case .destinationTooSmall:
            throw .destinationTooSmall(
                required: Int(byteLength),
                capacity: destination.count
            )
        case .memoryAccessFailed:
            throw .memoryAccessFailed
        case nil:
            throw .unexpectedRuntimeStatus(status)
        }
    }

    /// Calls the given closure with a pointer to a copy of the underlying bytes of the
    /// array's storage.
    ///
    /// - Note: The pointer passed as an argument to `body` is valid only for the
    /// lifetime of the closure. Do not escape it from the closure for later
    /// use.
    ///
    /// - Parameter body: A closure with an `UnsafeBufferPointer` parameter
    ///   that points to the contiguous storage for the array.
    ///    If `body` has a return value, that value is also
    ///   used as the return value for the `withUnsafeBytes(_:)` method. The
    ///   argument is valid only for the duration of the closure's execution.
    /// - Returns: The return value, if any, of the `body` closure parameter.
    public func withUnsafeBytes<R, E: Error>(_ body: (UnsafeBufferPointer<Element>) throws(E) -> R) throws(E) -> R {
        let buffer = UnsafeMutableBufferPointer<Element>.allocate(capacity: length)
        defer { buffer.deallocate() }
        copyMemory(to: buffer)
        let result = try body(UnsafeBufferPointer(buffer))
        return result
    }

    #if compiler(>=5.5)
    /// Calls the given async closure with a pointer to a copy of the underlying bytes of the
    /// array's storage.
    ///
    /// - Note: The pointer passed as an argument to `body` is valid only for the
    /// lifetime of the closure. Do not escape it from the async closure for later
    /// use.
    ///
    /// - Parameter body: A closure with an `UnsafeBufferPointer` parameter
    ///   that points to the contiguous storage for the array.
    ///    If `body` has a return value, that value is also
    ///   used as the return value for the `withUnsafeBytes(_:)` method. The
    ///   argument is valid only for the duration of the closure's execution.
    /// - Returns: The return value, if any, of the `body`async closure parameter.
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public func withUnsafeBytesAsync<R, E: Error>(
        _ body: (UnsafeBufferPointer<Element>) async throws(E) -> R
    ) async throws(E) -> R {
        let buffer = UnsafeMutableBufferPointer<Element>.allocate(capacity: length)
        defer { buffer.deallocate() }
        copyMemory(to: buffer)
        let result = try await body(UnsafeBufferPointer(buffer))
        return result
    }
    #endif

    /// Copies the contents of the array to the given buffer.
    ///
    /// - Parameter buffer: The buffer to copy the contents of the array to.
    ///   The buffer must have enough space to accommodate the contents of the array.
    public func copyMemory(to buffer: UnsafeMutableBufferPointer<Element>) {
        precondition(buffer.count >= length, "Buffer is too small to hold the contents of the array")
        do {
            try copyBytes(to: UnsafeMutableRawBufferPointer(buffer))
        } catch {
            preconditionFailure("Unable to copy JavaScript typed-array bytes: \(error)")
        }
    }
}

extension Int: TypedArrayElement {
    public static var typedArrayClass: JSObject {
        #if _pointerBitWidth(_32)
        return JSObject.global.Int32Array.object!
        #elseif _pointerBitWidth(_64)
        return JSObject.global.Int64Array.object!
        #else
        #error("Unsupported pointer width")
        #endif
    }
}

extension UInt: TypedArrayElement {
    public static var typedArrayClass: JSObject {
        #if _pointerBitWidth(_32)
        return JSObject.global.Uint32Array.object!
        #elseif _pointerBitWidth(_64)
        return JSObject.global.Uint64Array.object!
        #else
        #error("Unsupported pointer width")
        #endif
    }
}

extension Int8: TypedArrayElement {
    public static var typedArrayClass: JSObject { JSObject.global.Int8Array.object! }
}

extension UInt8: TypedArrayElement {
    public static var typedArrayClass: JSObject { JSObject.global.Uint8Array.object! }
}

extension Int16: TypedArrayElement {
    public static var typedArrayClass: JSObject { JSObject.global.Int16Array.object! }
}

extension UInt16: TypedArrayElement {
    public static var typedArrayClass: JSObject { JSObject.global.Uint16Array.object! }
}

extension Int32: TypedArrayElement {
    public static var typedArrayClass: JSObject { JSObject.global.Int32Array.object! }
}

extension UInt32: TypedArrayElement {
    public static var typedArrayClass: JSObject { JSObject.global.Uint32Array.object! }
}

extension Float32: TypedArrayElement {
    public static var typedArrayClass: JSObject { JSObject.global.Float32Array.object! }
}

extension Float64: TypedArrayElement {
    public static var typedArrayClass: JSObject { JSObject.global.Float64Array.object! }
}

public enum JSUInt8Clamped: TypedArrayElement {
    public typealias Element = UInt8
    public static var typedArrayClass: JSObject { JSObject.global.Uint8ClampedArray.object! }
}

public typealias JSUInt8ClampedArray = JSTypedArray<JSUInt8Clamped>

public typealias JSInt8Array = JSTypedArray<Int8>
public typealias JSUint8Array = JSTypedArray<UInt8>
public typealias JSInt16Array = JSTypedArray<Int16>
public typealias JSUint16Array = JSTypedArray<UInt16>
public typealias JSInt32Array = JSTypedArray<Int32>
public typealias JSUint32Array = JSTypedArray<UInt32>
public typealias JSFloat32Array = JSTypedArray<Float32>
public typealias JSFloat64Array = JSTypedArray<Float64>
