import { describe, expect, test } from "vitest";
import { SwiftRuntime } from "../src/index.js";

function makeRuntime(): {
    runtime: SwiftRuntime;
    memory: WebAssembly.Memory;
    freedHostFunctions: number[];
} {
    const memory = new WebAssembly.Memory({ initial: 1 });
    const freedHostFunctions: number[] = [];
    const runtime = new SwiftRuntime();
    runtime.setInstance({
        exports: {
            memory,
            swjs_library_version: () => 709,
            swjs_free_host_function: (id: number) => {
                freedHostFunctions.push(id);
            },
        },
    } as unknown as WebAssembly.Instance);
    return { runtime, memory, freedHostFunctions };
}

describe("Swift and JavaScript interop boundaries", () => {
    test("typed-array copying uses the exact intrinsic view", () => {
        const { runtime, memory } = makeRuntime();
        const imports = runtime.wasmImports as any;
        const objectSpace = (runtime as any).memory;
        const backing = new Uint8Array([0xaa, 7, 8, 9, 0xbb]);
        const view = backing.subarray(1, 4);
        Object.defineProperty(view, "byteLength", { value: 1000 });
        Object.defineProperty(view, "byteOffset", { value: 0 });
        Object.defineProperty(view, "buffer", {
            value: new ArrayBuffer(1000),
        });
        const ref = objectSpace.retain(view);
        const lengthPointer = 8;
        const destinationPointer = 32;

        const lengthStatus = imports.swjs_get_typed_array_byte_length(
            ref,
            lengthPointer,
        );
        const copyStatus = imports.swjs_copy_typed_array_bytes(
            ref,
            destinationPointer,
            3,
            lengthPointer,
        );

        expect(lengthStatus).toBe(0);
        expect(copyStatus).toBe(0);
        expect(new DataView(memory.buffer).getUint32(lengthPointer, true)).toBe(
            3,
        );
        expect(
            Array.from(new Uint8Array(memory.buffer, destinationPointer, 3)),
        ).toEqual([7, 8, 9]);
    });

    test("typed-array copying refuses an undersized destination", () => {
        const { runtime, memory } = makeRuntime();
        const imports = runtime.wasmImports as any;
        const objectSpace = (runtime as any).memory;
        const ref = objectSpace.retain(new Uint8Array([1, 2, 3]));
        const lengthPointer = 8;
        const destinationPointer = 32;
        new Uint8Array(memory.buffer, destinationPointer, 3).fill(0xcc);

        const status = imports.swjs_copy_typed_array_bytes(
            ref,
            destinationPointer,
            2,
            lengthPointer,
        );

        expect(status).toBe(3);
        expect(new DataView(memory.buffer).getUint32(lengthPointer, true)).toBe(
            3,
        );
        expect(
            Array.from(new Uint8Array(memory.buffer, destinationPointer, 3)),
        ).toEqual([0xcc, 0xcc, 0xcc]);
    });

    test("typed-array intrinsic access rejects a Proxy", () => {
        const { runtime } = makeRuntime();
        const imports = runtime.wasmImports as any;
        const objectSpace = (runtime as any).memory;
        const ref = objectSpace.retain(new Proxy(new Uint8Array([1]), {}));

        expect(imports.swjs_get_typed_array_byte_length(ref, 8)).toBe(1);
    });

    test("a cancelled oneshot function is inert when invoked late", () => {
        const { runtime } = makeRuntime();
        const imports = runtime.wasmImports as any;
        const objectSpace = (runtime as any).memory;
        const fileRef = objectSpace.retain("interop-boundaries.test.ts");
        const functionRef = imports.swjs_create_oneshot_function(
            123,
            1,
            fileRef,
        );
        const functionObject = objectSpace.getObject(functionRef);

        imports.swjs_cancel_oneshot_function(functionRef);

        expect(functionObject()).toBeUndefined();
    });

    test("cancelling an already released oneshot reference is idempotent", () => {
        const { runtime } = makeRuntime();
        const imports = runtime.wasmImports as any;
        const objectSpace = (runtime as any).memory;
        const fileRef = objectSpace.retain("interop-boundaries.test.ts");
        const functionRef = imports.swjs_create_oneshot_function(
            123,
            1,
            fileRef,
        );
        imports.swjs_release(functionRef);

        expect(() =>
            imports.swjs_cancel_oneshot_function(functionRef),
        ).not.toThrow();
    });

    test("cancelling a linked oneshot releases and deactivates its peer", () => {
        const { runtime, freedHostFunctions } = makeRuntime();
        const imports = runtime.wasmImports as any;
        const objectSpace = (runtime as any).memory;
        const fileRef = objectSpace.retain("interop-boundaries.test.ts");
        const firstRef = imports.swjs_create_oneshot_function(123, 1, fileRef);
        const secondRef = imports.swjs_create_oneshot_function(456, 1, fileRef);
        const secondFunction = objectSpace.getObject(secondRef);
        imports.swjs_link_oneshot_functions(firstRef, secondRef);

        imports.swjs_cancel_oneshot_function(firstRef);

        expect(freedHostFunctions).toEqual([456]);
        expect(secondFunction()).toBeUndefined();
    });
});
