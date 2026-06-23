# Embedded example

This example builds JavaScriptKit with Embedded Swift for WebAssembly.

Requirements:

- Swift 6.3.1 toolchain
- `swift-6.3.1-RELEASE_wasm-embedded` Swift SDK

Use `SWIFT_BIN` when the active `swift` is not the 6.3.1 toolchain:

```sh
export SWIFT_BIN="$(swiftly run +6.3.1 which swift)"
./build.sh
npm install
npx serve ../..
```

Set `SWIFT_SDK_ID` to override the SDK identifier. The default base SDK is
`swift-6.3.1-RELEASE_wasm`, and `build.sh` resolves it to
`swift-6.3.1-RELEASE_wasm-embedded`. You may pass either the base SDK or the
full embedded SDK identifier.

## Size comparison

Run the same example as standard WASM and Embedded WASM:

```sh
export SWIFT_BIN="/Users/1amageek/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin/swift"
./measure-size.sh
```

The script writes:

- `.build/size-comparison/standard/Package`
- `.build/size-comparison/embedded/Package`
- `.build/size-comparison/size-report.json`

On the current Swift 6.3.1 toolchain, without `wasm-opt`, this example measured:

| Encoding | Standard | Embedded | Reduction |
|---|---:|---:|---:|
| raw | 8,968,053 bytes | 832,001 bytes | 90.7% |
| gzip -9 | 2,405,936 bytes | 277,845 bytes | 88.5% |
| brotli -q 11 | 1,727,158 bytes | 224,900 bytes | 87.0% |

## Browser smoke test

Build the Embedded package, install the JavaScript test dependencies, then run
the browser smoke test:

```sh
./build.sh
npm install
npm run test:embedded-example
```

The smoke test serves `index.html` locally with the generated PackageToJS output,
opens Chrome through Playwright, clicks the counter button, and verifies the
UTF-8 encoder output.
