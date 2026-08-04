import _CJavaScriptKit

/// A `JSFunction` wrapper that enables throwing function calls.
/// Exceptions produced by JavaScript functions will be thrown as `JSException`.
public class JSThrowingFunction {
    private let base: JSObject
    public init(_ base: JSObject) {
        self.base = base
    }

    /// Calls this function with JavaScript values and an optional `this` context.
    @discardableResult
    public func callAsFunction(
        this: JSObject? = nil,
        arguments: [JSValue]
    ) throws(JSException) -> JSValue {
        try invokeJSFunction(base, arguments: arguments, this: this)
    }

    #if !hasFeature(Embedded)
    /// Call this function with given `arguments` and binding given `this` as context.
    /// - Parameters:
    ///   - this: The value to be passed as the `this` parameter to this function.
    ///   - arguments: Arguments to be passed to this function.
    /// - Returns: The result of this call.
    @discardableResult
    public func callAsFunction(this: JSObject? = nil, arguments: [ConvertibleToJSValue]) throws(JSException) -> JSValue
    {
        try invokeJSFunction(
            base,
            arguments: arguments.map(\.jsValue),
            this: this
        )
    }

    /// A variadic arguments version of `callAsFunction`.
    @discardableResult
    public func callAsFunction(
        this: JSObject? = nil,
        _ arguments: ConvertibleToJSValue...
    ) throws(JSException) -> JSValue {
        try self(this: this, arguments: arguments)
    }

    /// Instantiate an object from this function as a throwing constructor.
    ///
    /// Guaranteed to return an object because either:
    ///
    /// - a. the constructor explicitly returns an object, or
    /// - b. the constructor returns nothing, which causes JS to return the `this` value, or
    /// - c. the constructor returns undefined, null or a non-object, in which case JS also returns `this`.
    ///
    /// - Parameter arguments: Arguments to be passed to this constructor function.
    /// - Returns: A new instance of this constructor.
    public func new(arguments: [ConvertibleToJSValue]) throws(JSException) -> JSObject {
        try new(arguments: arguments.map(\.jsValue))
    }

    /// A variadic arguments version of `new`.
    public func new(_ arguments: ConvertibleToJSValue...) throws(JSException) -> JSObject {
        try new(arguments: arguments)
    }
    #endif

    /// Instantiates an object while preserving a JavaScript constructor exception.
    public func new(arguments: [JSValue]) throws(JSException) -> JSObject {
        try arguments.withRawJSValues { rawValues -> Result<JSObject, JSException> in
            rawValues.withUnsafeBufferPointer { bufferPointer in
                let argv = bufferPointer.baseAddress
                let argc = bufferPointer.count

                var exceptionRawKind = JavaScriptRawValueKindAndFlags()
                var exceptionPayload1 = JavaScriptPayload1()
                var exceptionPayload2 = JavaScriptPayload2()
                let resultObj = swjs_call_throwing_new(
                    self.base.id,
                    argv,
                    Int32(argc),
                    &exceptionRawKind,
                    &exceptionPayload1,
                    &exceptionPayload2
                )
                let exceptionKind = JavaScriptValueKindAndFlags(bitPattern: exceptionRawKind)
                if exceptionKind.isException {
                    let exception = RawJSValue(
                        kind: exceptionKind.kind,
                        payload1: exceptionPayload1,
                        payload2: exceptionPayload2
                    )
                    return .failure(JSException(exception.jsValue))
                }
                return .success(JSObject(id: resultObj))
            }
        }.get()
    }
}

private func invokeJSFunction(
    _ jsFunc: JSObject,
    arguments: [JSValue],
    this: JSObject?
) throws(JSException) -> JSValue {
    #if Tracing
    let jsValues = arguments.map { $0.jsValue }
    let traceEnd = JSTracingHooks.beginJSCall(
        this.map {
            .method(receiver: $0, methodName: nil, arguments: jsValues)
        } ?? .function(function: jsFunc, arguments: jsValues)
    )
    defer { traceEnd?() }
    #endif
    let id = jsFunc.id
    let (result, isException) = arguments.withRawJSValues { rawValues in
        rawValues.withUnsafeBufferPointer { bufferPointer -> (JSValue, Bool) in
            let argv = bufferPointer.baseAddress
            let argc = bufferPointer.count
            let kindAndFlags: JavaScriptValueKindAndFlags
            var payload1 = JavaScriptPayload1()
            var payload2 = JavaScriptPayload2()
            if let thisId = this?.id {
                let resultBitPattern = swjs_call_function_with_this(
                    thisId,
                    id,
                    argv,
                    Int32(argc),
                    &payload1,
                    &payload2
                )
                kindAndFlags = JavaScriptValueKindAndFlags(bitPattern: resultBitPattern)
            } else {
                let resultBitPattern = swjs_call_function(
                    id,
                    argv,
                    Int32(argc),
                    &payload1,
                    &payload2
                )
                kindAndFlags = JavaScriptValueKindAndFlags(bitPattern: resultBitPattern)
            }
            let result = RawJSValue(kind: kindAndFlags.kind, payload1: payload1, payload2: payload2)
            return (result.jsValue, kindAndFlags.isException)
        }
    }
    if isException {
        throw JSException(result)
    }
    return result
}

#if hasFeature(Embedded)
// Embedded Swift cannot form an existential variadic parameter. These generic
// overloads preserve the ordinary throwing-call surface for zero through seven
// arguments while the implementation continues to use one `[JSValue]` path.
extension JSThrowingFunction {
    @discardableResult
    public func callAsFunction(this: JSObject) throws(JSException) -> JSValue {
        try self(this: this, arguments: [])
    }

    @discardableResult
    public func callAsFunction(
        this: JSObject,
        _ arg0: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(this: this, arguments: [arg0.jsValue])
    }

    @discardableResult
    public func callAsFunction(
        this: JSObject,
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(this: this, arguments: [arg0.jsValue, arg1.jsValue])
    }

    @discardableResult
    public func callAsFunction(
        this: JSObject,
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(this: this, arguments: [arg0.jsValue, arg1.jsValue, arg2.jsValue])
    }

    @discardableResult
    public func callAsFunction(
        this: JSObject,
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue,
        _ arg3: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(
            this: this,
            arguments: [
                arg0.jsValue, arg1.jsValue, arg2.jsValue, arg3.jsValue,
            ]
        )
    }

    @discardableResult
    public func callAsFunction(
        this: JSObject,
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue,
        _ arg3: some ConvertibleToJSValue,
        _ arg4: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(
            this: this,
            arguments: [
                arg0.jsValue, arg1.jsValue, arg2.jsValue, arg3.jsValue,
                arg4.jsValue,
            ]
        )
    }

    @discardableResult
    public func callAsFunction(
        this: JSObject,
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue,
        _ arg3: some ConvertibleToJSValue,
        _ arg4: some ConvertibleToJSValue,
        _ arg5: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(
            this: this,
            arguments: [
                arg0.jsValue, arg1.jsValue, arg2.jsValue, arg3.jsValue,
                arg4.jsValue, arg5.jsValue,
            ]
        )
    }

    @discardableResult
    public func callAsFunction(
        this: JSObject,
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue,
        _ arg3: some ConvertibleToJSValue,
        _ arg4: some ConvertibleToJSValue,
        _ arg5: some ConvertibleToJSValue,
        _ arg6: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(
            this: this,
            arguments: [
                arg0.jsValue, arg1.jsValue, arg2.jsValue, arg3.jsValue,
                arg4.jsValue, arg5.jsValue, arg6.jsValue,
            ]
        )
    }

    @discardableResult
    public func callAsFunction() throws(JSException) -> JSValue {
        try self(arguments: [])
    }

    @discardableResult
    public func callAsFunction(
        _ arg0: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(arguments: [arg0.jsValue])
    }

    @discardableResult
    public func callAsFunction(
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(arguments: [arg0.jsValue, arg1.jsValue])
    }

    @discardableResult
    public func callAsFunction(
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(arguments: [arg0.jsValue, arg1.jsValue, arg2.jsValue])
    }

    @discardableResult
    public func callAsFunction(
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue,
        _ arg3: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(arguments: [
            arg0.jsValue, arg1.jsValue, arg2.jsValue, arg3.jsValue,
        ])
    }

    @discardableResult
    public func callAsFunction(
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue,
        _ arg3: some ConvertibleToJSValue,
        _ arg4: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(arguments: [
            arg0.jsValue, arg1.jsValue, arg2.jsValue, arg3.jsValue,
            arg4.jsValue,
        ])
    }

    @discardableResult
    public func callAsFunction(
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue,
        _ arg3: some ConvertibleToJSValue,
        _ arg4: some ConvertibleToJSValue,
        _ arg5: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(arguments: [
            arg0.jsValue, arg1.jsValue, arg2.jsValue, arg3.jsValue,
            arg4.jsValue, arg5.jsValue,
        ])
    }

    @discardableResult
    public func callAsFunction(
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue,
        _ arg3: some ConvertibleToJSValue,
        _ arg4: some ConvertibleToJSValue,
        _ arg5: some ConvertibleToJSValue,
        _ arg6: some ConvertibleToJSValue
    ) throws(JSException) -> JSValue {
        try self(arguments: [
            arg0.jsValue, arg1.jsValue, arg2.jsValue, arg3.jsValue,
            arg4.jsValue, arg5.jsValue, arg6.jsValue,
        ])
    }

    public func new() throws(JSException) -> JSObject {
        try new(arguments: [])
    }

    public func new(
        _ arg0: some ConvertibleToJSValue
    ) throws(JSException) -> JSObject {
        try new(arguments: [arg0.jsValue])
    }

    public func new(
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue
    ) throws(JSException) -> JSObject {
        try new(arguments: [arg0.jsValue, arg1.jsValue])
    }

    public func new(
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue
    ) throws(JSException) -> JSObject {
        try new(arguments: [arg0.jsValue, arg1.jsValue, arg2.jsValue])
    }

    public func new(
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue,
        _ arg3: some ConvertibleToJSValue
    ) throws(JSException) -> JSObject {
        try new(arguments: [arg0.jsValue, arg1.jsValue, arg2.jsValue, arg3.jsValue])
    }

    public func new(
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue,
        _ arg3: some ConvertibleToJSValue,
        _ arg4: some ConvertibleToJSValue
    ) throws(JSException) -> JSObject {
        try new(arguments: [arg0.jsValue, arg1.jsValue, arg2.jsValue, arg3.jsValue, arg4.jsValue])
    }

    public func new(
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue,
        _ arg3: some ConvertibleToJSValue,
        _ arg4: some ConvertibleToJSValue,
        _ arg5: some ConvertibleToJSValue
    ) throws(JSException) -> JSObject {
        try new(arguments: [
            arg0.jsValue, arg1.jsValue, arg2.jsValue, arg3.jsValue,
            arg4.jsValue, arg5.jsValue,
        ])
    }

    public func new(
        _ arg0: some ConvertibleToJSValue,
        _ arg1: some ConvertibleToJSValue,
        _ arg2: some ConvertibleToJSValue,
        _ arg3: some ConvertibleToJSValue,
        _ arg4: some ConvertibleToJSValue,
        _ arg5: some ConvertibleToJSValue,
        _ arg6: some ConvertibleToJSValue
    ) throws(JSException) -> JSObject {
        try new(arguments: [
            arg0.jsValue, arg1.jsValue, arg2.jsValue, arg3.jsValue,
            arg4.jsValue, arg5.jsValue, arg6.jsValue,
        ])
    }
}
#endif
