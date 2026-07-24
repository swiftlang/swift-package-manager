// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "MacroWithDirectTestDependency",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .target(name: "MacroImplHelpers"),
        .macro(name: "MacroImpl", dependencies: ["MacroImplHelpers"]),
        .target(name: "MacroDef", dependencies: ["MacroImpl"]),
        .testTarget(name: "MacroImplTests", dependencies: ["MacroImpl", "MacroDef"]),
    ],
    swiftLanguageModes: [.v5]
)
