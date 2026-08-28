# Embedded resource representations

`run.sh` compares SwiftPM's existing byte-array resource embedding with the
object-file prototype. It builds two equivalent release executables, records
build wall time and peak resident memory, and then runs both executables while
reading every byte of the resource.

The benchmark needs a SwiftPM executable and `PackageDescription` runtime built
from this branch, plus a toolchain `llvm-objcopy`:

```sh
Benchmarks/EmbeddedResources/run.sh \
  /path/to/swift-build \
  /path/to/llvm-objcopy \
  /path/to/lib/swift/pm \
  32
```

The final argument is the payload size in MiB. Results and complete command
output are written to `${TMPDIR:-/tmp}/swiftpm-embedded-resource-benchmark`.
The default is 8 MiB, which is large enough to expose the scalability problem
without generating the much larger intermediate source produced by a 32 MiB
input.
