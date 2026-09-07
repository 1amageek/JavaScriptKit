# JavaScriptKit Package Design

## Purpose and Scope

This document is the package design authority for JavaScriptKit. The package
bridges Swift WebAssembly programs to JavaScript values and functions and
provides optional event-loop, generated-binding, and compatibility products.

The JavaScript event-loop executor is specified by the child design below.
Other package products retain their existing public contracts and are outside
the executor-integration change.

## Responsibilities and Boundaries

The package owns Swift-to-JavaScript representation, call, closure, promise,
and executor adapters. The Swift concurrency runtime owns task and MainActor
semantics; JavaScriptKit supplies the selected WebAssembly executor but does
not redefine task cancellation, error propagation, or actor isolation.

The package does not own Swift SDK implementation, application actor systems,
Cloudflare hosting, or downstream transport policy.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [JavaScriptEventLoop](Sources/JavaScriptEventLoop/DESIGN.md) | child | JavaScript main/default executor integration | Maps Swift jobs to the JavaScript event loop. | Recheck fixed Swift runtime SPI behavior when advancing the toolchain. |

## Architecture

```text
Swift WebAssembly application
    -> JavaScriptKit values and calls
    -> JavaScriptEventLoop executor adapter
    -> JavaScript microtasks and timers
```

## Contracts and Invariants

- JavaScript values cross the WebAssembly boundary through the existing bridge
  ownership and conversion contracts.
- Executor installation must precede creation of application tasks that depend
  on JavaScript progress.
- Standard and Embedded profiles preserve Swift task identity, actor isolation,
  cancellation, and thrown failures while selecting supported executor
  capabilities for their fixed runtime.

## Verification and Change Impact

Changes to JavaScript values or calls require their bridge suites. Changes to
the event-loop executor require the child design's focused owner tests and
actual Standard and Embedded WebAssembly runtime evidence. Downstream packages
must adopt unreleased fixes by exact immutable revision and validate the path
they actually select.
