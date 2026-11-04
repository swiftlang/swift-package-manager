// swift-tools-version:999.0
import PackageDescription

let package = Package(
    name: "producer",
    products: [
        .library(
            name: "Paper",
            targets: ["Paper"],
        ),
        .library(
            name: "PaperLegacy",
            targets: ["PaperLegacy"],
            deprecated: .unsupported(
                message: "PaperLegacy is superseded by Paper.",
                replacement: .renamed("Paper"),
            ),
        ),
        .library(
            name: "PaperExperimental",
            targets: ["PaperExperimental"],
            deprecated: .unsupported(
                message: "PaperExperimental is going away with no replacement.",
            ),
        ),
        .executable(
            name: "paper-tool-old",
            targets: ["paper-tool-old"],
            deprecated: .unsupported(
                message: "Migrate to the standalone paper-tools package.",
                replacement: .renamed("paper-tool", package: "paper-tools"),
            ),
        ),
    ],
    targets: [
        .target(name: "Paper"),
        .target(name: "PaperLegacy", dependencies: ["Paper"]),
        .target(name: "PaperExperimental"),
        .executableTarget(name: "paper-tool-old"),
    ]
)
