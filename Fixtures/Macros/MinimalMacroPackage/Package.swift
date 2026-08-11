// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "MinimalMacroPackage",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .target(name: "MacroImplHelpers"),
        .macro(name: "MacroImpl", dependencies: ["MacroImplHelpers"]),
        .target(name: "MacroDef", dependencies: ["MacroImpl"]),
        .executableTarget(name: "MacroClient", dependencies: ["MacroDef"]),
        .testTarget(name: "MinimalMacroPackageTests", dependencies: ["MacroDef"]),
    ],
    swiftLanguageModes: [.v5]
)
