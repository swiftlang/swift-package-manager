// swift-tools-version: 999.0
import PackageDescription

// The trait-bearing sibling workspace member for the S15_MemberTraits
// fixture. Declares three trait names — `"core"`, `"extras"`,
// and `"perf"` — so downstream `.package(workspaceMember:)`
// consumers can request any combination. `LibA` is the sole
// product both consumers import.
let package = Package(
    name: "lib-a",
    products: [
        .library(name: "LibA", targets: ["LibA"]),
    ],
    traits: [
        .default(enabledTraits: ["core"]),
        .trait(name: "core"),
        .trait(name: "extras"),
        .trait(name: "perf"),
    ],
    targets: [
        .target(name: "LibA"),
    ],
)
