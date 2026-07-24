// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacroImplHelpers",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "MacroImplHelpers", targets: ["MacroImplHelpers"]),
    ],
    targets: [
        .target(name: "MacroImplHelpers"),
    ],
    swiftLanguageModes: [.v5]
)
