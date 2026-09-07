# JavaScriptEventLoop

## Purpose and Scope

`JavaScriptEventLoop` adapts Swift concurrency jobs to the JavaScript event
loop. This module design is a child of the [JavaScriptKit package design](../../DESIGN.md).
It covers installation and execution of main, immediate default, and supported
delayed jobs for Standard and Embedded WebAssembly.

## Responsibilities and Boundaries

This module owns executor capability selection, mapping accepted jobs to its
existing serial event-loop queue, and handing queued work to JavaScript
microtasks or timers. Swift owns MainActor and task semantics. The application
owns calling `installGlobalExecutor()` before creating dependent tasks.

The module does not own Swift SDK behavior, application clocks, distributed
actor transports, or Cloudflare host lifecycle. Embedded does not gain a
delayed-task API that its fixed SDK marks unavailable.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [JavaScriptKit package](../../DESIGN.md) | parent | JavaScript bridge and profile support | Provides the bridge used to enqueue JavaScript callbacks. | Boundary ownership must remain unchanged. |
| [SwiftWeb ClientRuntime](https://github.com/1amageek/swift-web/blob/main/Sources/SwiftWebBrowser/ClientRuntime/DESIGN.md) | used by | Installed JavaScript main/default executor | Its WASM Actor transport requires asynchronous JavaScript progress. | SwiftWeb consumes an immutable Git revision. |

## Architecture

```text
installGlobalExecutor()
    -> fixed Swift 6.4 ExecutorFactory
       -> MainActor executor ----+
       -> immediate default -----+-> JavaScriptEventLoop.shared
                                      -> serial queue -> JS microtask
    -> compatible legacy hooks
       -> remaining legacy global/delay runtime entry points

Embedded delayed SchedulingExecutor: not advertised
```

## Contracts and Invariants

| Profile | MainActor owner | Immediate default owner | Delayed scheduling |
|---|---|---|---|
| Standard WASM on the fixed Swift 6.4 runtime | `ExecutorFactory.mainExecutor` | `ExecutorFactory.defaultExecutor` | Existing `SchedulingExecutor` implementation |
| Embedded WASM on the fixed Swift 6.4 runtime | `ExecutorFactory.mainExecutor` | `ExecutorFactory.defaultExecutor` | Not advertised because the SDK excludes the scheduling route and marks task sleep unavailable |
| Runtime/toolchain combinations outside the factory condition | Existing legacy hooks | Existing legacy hooks | Existing legacy delay hooks where supported |

- On the fixed Embedded SDK, factory installation is authoritative for both
  MainActor and immediate default jobs. Installing only the legacy MainActor
  hook is insufficient because that runtime enqueues through its MainExecutor
  witness.
- Compatible legacy hooks remain installed for runtime entry points outside
  the factory contract. They must not cause a job accepted by the factory to be
  enqueued twice.
- Embedded executor types do not conform to `SchedulingExecutor` when their
  only implementation would terminate. Unsupported delayed scheduling remains
  unavailable rather than becoming a silent fallback.
- Every accepted immediate job is queued exactly once on the existing serial
  JavaScript event loop. Queue storage, ordering, `Sendable` declarations, and
  the install-before-first-task/idempotence contract remain unchanged.
- Executor adaptation does not catch, remap, or discard task failures or
  cancellation. A hop to MainActor preserves MainActor isolation.

## Runtime Flows

1. The application installs `JavaScriptEventLoop` before creating dependent
   tasks.
2. The fixed Swift runtime records JavaScriptKit's factory as its MainActor and
   default immediate executor provider.
3. A default or detached task is queued through the default executor.
4. `MainActor.run` enqueues through the factory's MainExecutor witness.
5. Both immediate paths enter the existing serial JavaScript event-loop queue
   and resume from a JavaScript microtask.

## State, Ownership, and Lifecycle

The existing per-thread/shared event-loop instance owns queued jobs and
JavaScript scheduling closures. This change introduces no new mutable state,
registry, detached owner, or shutdown API. Installation remains idempotent and
must occur before task creation; job and closure lifetimes remain owned by the
existing queue and JavaScript callback adapters.

The fixed `swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a` WASI profile
comparison is scoped to the existing owner; it does not add synchronization
or change the library's runtime-thread selection.

| Ownership or capability | Standard WASM | Embedded WASM |
|---|---|---|
| Storage and lifetime | Existing `_shared`, `QueueState`, scheduling closures, and installation flag | Same declarations and owner lifetime; no Embedded storage replacement |
| Read and mutation entry points | Existing `shared`, `installGlobalExecutorIsolated`, enqueue, and queue-drain paths | Same paths after factory or compatible legacy entry |
| Isolation and Sendable | Existing serial executor and `@unchecked Sendable` declaration | Unchanged declaration and serial executor contract |
| Immediate executor installation | Existing factory | Factory plus retained legacy compatibility entries |
| `SchedulingExecutor` | Loop and `CurrentThread` conformances | Neither conformance is compiled |

## Failure, Concurrency, and Constraints

Embedded task-sleep and generic delayed-scheduling APIs remain unavailable on
the fixed SDK. The executor must not expose a capability implemented only by a
fatal branch. Main/default execution remains serial on the JavaScript event
loop, and the change must not weaken actor isolation or the existing queue's
thread/profile contract.

## Verification and Change Impact

The existing Embedded example owns the JavaScriptKit regression: after
installing the executor before task creation, a detached/default task must run,
hop to MainActor, publish exactly one completion marker, and leave no browser
error. Focused owner compile/tests preserve Standard behavior.

The pinned Debug owner checks passed the existing Embedded browser example
(detached-to-MainActor completion exactly once, counter interaction, and UTF-8
output) and all 12 selected `JavaScriptEventLoopTests`, including task sleep,
priority, and throwing paths. The existing SwiftPM `description.json` files
record `-Onone` for both profiles and SDK-provided `Embedded` plus `-wmo` only
for Embedded. The compiled `JavaScriptEventLoop.build/*.swift.o` objects retain
the `CurrentThread` MainExecutor witness in both profiles; Standard contains
both SchedulingExecutor conformances, while Embedded contains no
SchedulingExecutor symbols. The downstream Embedded installation object also
calls the JavaScriptEventLoop-specialized `swift_createExecutors` before its
legacy compatibility installation. These checks use existing build artifacts,
not a substitute module-interface build.

SwiftWeb's existing ActorTransportBoundary fixture is the downstream proof. A
same-scratch local edit first proves the candidate source was selected; after
review and push, an exact public JavaScriptKit revision must pass both pinned
Standard and Embedded builds and runtime checks for 1 MiB content, errors,
cancellation, shutdown, copy accounting, and cleanup. Compile/link without the
MainActor completion marker is not sufficient.
