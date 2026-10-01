# Deprecating package products

Signal to consumers that a product should no longer be used, optionally
pointing them at a replacement.

## Overview

When you evolve a package, you sometimes need to steer consumers off of a
product you can no longer support — because it's been superseded by a
better-designed replacement, moved to a different package, or is being
retired entirely. Swift Package Manager lets you record that intent
directly in `Package.swift`, so consumers see a diagnostic at build time
and can survey the state of their dependency graph on demand.

Use the `deprecated:` parameter on `.library(...)`, `.executable(...)`, or
`.plugin(...)` to mark a product as unsupported. The parameter accepts a
value produced by `Product.Deprecation.unsupported(message:replacement:)`.
Both `message:` and `replacement:` are optional — omit them both to signal
a bare "unsupported" state with no additional guidance.

```swift
// swift-tools-version: 6.5
import PackageDescription

let package = Package(
    name: "Paper",
    products: [
        .library(name: "Paper", targets: ["Paper"]),

        // Replaced by another product in the same package.
        .library(
            name: "PaperLegacy",
            targets: ["PaperLegacy"],
            deprecated: .unsupported(
                message: "PaperLegacy is superseded by Paper.",
                replacement: .renamed("Paper")
            )
        ),

        // Retired with no advertised replacement.
        .library(
            name: "PaperExperimental",
            targets: ["PaperExperimental"],
            deprecated: .unsupported(
                message: "PaperExperimental is going away with no replacement."
            )
        ),

        // Superseded by a product in another package.
        .executable(
            name: "paper-tool-old",
            targets: ["paper-tool-old"],
            deprecated: .unsupported(
                message: "Migrate to the standalone paper-tools package.",
                replacement: .renamed("paper-tool", package: "paper-tools")
            )
        ),
    ],
    targets: [
        .target(name: "Paper"),
        .target(name: "PaperLegacy", dependencies: ["Paper"]),
        .target(name: "PaperExperimental"),
        .executableTarget(name: "paper-tool-old"),
    ]
)
```

The `deprecated:` parameter is optional and defaults to `nil`. Existing
packages are unaffected.

### Describing the replacement

`Product.Deprecation.Replacement` has a single factory,
`.renamed(_ product:package:)`, that identifies the product a consumer
should adopt in place of the unsupported product.

- Omit `package:` when the replacement lives in the same package as the
  deprecated product. Example: `.renamed("Paper")`.
- Pass `package:` when the replacement lives in a different package that
  consumers must already depend on. Example:
  `.renamed("paper-tool", package: "paper-tools")`.

Swift Package Manager does not verify that a replacement product actually
exists in the referenced package — unresolved names are surfaced as-is in
the diagnostic, mirroring how `@available(_, renamed:)` behaves in the
Swift compiler.

## Diagnostic behavior for consumers

When a consumer package's target depends on a deprecated product, Swift
Package Manager emits a warning through its diagnostic system during graph
resolution. `swift build`, `swift test` and `swift package resolve` all
surface the diagnostic. The warning text is derived from the `message:`
(if any) and the `replacement:` locator:

- Same-package replacement — appended sentence: `Use 'X' instead.`
- Cross-package replacement — appended sentence:
  `Use 'X' from package 'P' instead.`
- No replacement — no additional sentence; the message alone is emitted.

The warning is emitted once per consuming target that references the
deprecated product. It is emitted by SwiftPM itself (not by the Swift
compiler), so it applies uniformly to libraries, executables, and plugins.

If the consuming target opts into `.treatAllWarnings(as: .error)` in its
Swift build settings, or if the build invocation passes
`-Xswiftc -warnings-as-errors`, the deprecation diagnostic is escalated
from a warning to an error, matching how the compiler treats its own
deprecation diagnostics.

## Interaction with `dump-package`

The output of <doc:PackageDumpPackage> gains an optional `deprecation`
object on each deprecated product, with the following shape:

```json
{
  "message": "PaperLegacy is superseded by Paper.",
  "replacement": {
    "kind": "renamed",
    "product": "Paper"
  }
}
```

The `replacement` object always has `kind: "renamed"` and a `product`
string. A `package` field is present only when the replacement lives in a
different package. Products without a `deprecated:` argument have no
`deprecation` key in the dumped JSON, so existing consumers of
`dump-package` output are unaffected.

## Tools-version requirement

Manifests that declare `deprecated:` require a Swift tools-version of
`6.5` or later. Older tools versions parse the manifest without
recognizing the parameter, matching how other version-gated `Package.swift`
API is handled.
