# Results

Measured on an Apple silicon Mac running macOS 26.4 with Apple Swift 6.3 and
LLVM 21 `llvm-objcopy`. Both release executables iterate over every resource
byte and print the same checksum.

## 1 MiB payload

| Representation | Generated Swift | Build time | Peak build RSS | Executable | Peak runtime RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Byte array | 3,744,333 B | 67.33 s | 7,197,032,448 B | 1,114,504 B | 2,605,056 B |
| Object file | 409 B | 1.28 s | 103,251,968 B | 1,115,048 B | 2,605,056 B |

## 8 MiB payload

The byte-array build generated 29,950,794 bytes of Swift source, reached a peak
RSS of 13,700,726,784 bytes, and failed after 31.07 seconds because the compiler
could not type-check the expression in reasonable time.

The object-file build generated 409 bytes of Swift source and completed in 1.88
seconds with a peak RSS of 103,448,576 bytes. Its executable was 8,512,424 bytes
and produced the expected checksum after reading all 8,388,608 resource bytes.

## Interpretation

The object-file representation removes the resource payload from Swift source,
so source generation and compilation stay approximately constant as the file
grows. Executable sizes remain comparable.

The benchmark does **not** show a runtime-memory reduction. The existing
`[UInt8]` literal is already emitted as static storage by the compiler, and both
1 MiB executables had the same measured maximum resident set size. The measured
benefit is build time and build memory, plus the ability to compile resources
that make the source representation fail.
