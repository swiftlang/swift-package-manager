# Exploring object-file resource embedding in SwiftPM

SwiftPM's `Resource.embedInCode` is convenient, but its current representation
does not scale well. Package Manager reads the resource and generates a Swift
array literal containing every byte as a decimal integer:

```swift
static let payload_bin: [UInt8] = [123, 0, 33, 100, 99 /* ... */]
```

That makes the resource available without a separate file at runtime, but it
also makes the Swift parser and type checker process a source expression that
can be several times larger than the original data.

I have been exploring a second, opt-in representation:

```swift
.embedInCode("payload.bin", representation: .objectFile)
```

For this mode, SwiftPM creates a small target-native object and uses the
toolchain's `llvm-objcopy` to inject the resource section and its data symbol.
Mach-O requires a pre-sized section that `objcopy` updates, while ELF supports
adding the section and symbol directly. The generated Swift source declares
the linked data symbol and exposes its bytes as an `UnsafeRawBufferPointer`:

```swift
@_silgen_name("swiftpm_resource_Benchmark_payload_bin_data")
nonisolated(unsafe) private var _payload: UInt8

static var payload_bin: UnsafeRawBufferPointer {
    let start = withUnsafePointer(to: &_payload) { UnsafeRawPointer($0) }
    return UnsafeRawBufferPointer(start: start, count: 8_388_608)
}
```

The accessor's undefined data-symbol reference lets the linker extract the
resource object correctly when a Swift target is packaged as a static archive,
without requiring whole-archive linker options.

## Initial results

With a 1 MiB payload, the existing representation generated 3.7 MiB of Swift
source and took 67 seconds to build, peaking at 7.2 GB of resident memory. The
object-file representation generated 409 bytes of Swift source and built in
1.3 seconds with about 103 MB peak RSS.

At 8 MiB, the existing representation generated almost 30 MiB of source and
failed because the compiler could not type-check the expression in reasonable
time. The object-file version still generated 409 bytes of Swift and built in
under two seconds.

One assumption did not survive measurement: this is not currently a runtime
memory optimization. The compiler already emits the `[UInt8]` literal as static
storage, and the two 1 MiB executables had the same measured runtime RSS while
reading every byte. The win is removing the payload from the Swift parsing and
type-checking pipeline.

## Open questions

This prototype supports Mach-O and ELF through SwiftPM's native build system.
The default Swift Build backend needs equivalent task support before this can
be considered a complete SwiftPM feature.

`Span` is also an interesting API direction because it expresses a non-owning
view over contiguous memory. A static computed property cannot safely return a
non-escapable `Span`, though, so that likely requires a closure-based API such
as `withPayload { span in ... }`. The prototype uses
`UnsafeRawBufferPointer` to keep the experiment focused on the build pipeline.

The implementation and reproducible benchmark are available on the experiment
branch. I would be interested in feedback on the manifest API, the generated
accessor type, and how this should integrate with Swift Build.
