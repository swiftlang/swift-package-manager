// swift-tools-version: 999.0
import PackageDescription

// The trait-bearing external dependency for the S15_InheritedTraits
// fixture. Declares three trait names — `"core"`, `"extras"`, and
// `"perf"` — so a downstream consumer can request any combination.
// The `TraitedLib` product is unconditional (both workspace members
// need to import it), while the trait names themselves are what the
// resolver isolates per-member via `.package(workspaceInherited:
// traits:)`.
let package = Package(
    name: "traited-lib",
    products: [
        .library(name: "TraitedLib", targets: ["TraitedLib"]),
    ],
    traits: [
        .default(enabledTraits: ["core"]),
        .trait(name: "core"),
        .trait(name: "extras"),
        .trait(name: "perf"),
    ],
    targets: [
        .target(name: "TraitedLib"),
    ],
)
