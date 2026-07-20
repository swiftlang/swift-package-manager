// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "MinimalWebAssemblyMacroPackage",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(path: "MacroImplHelpers"),
    ],
    targets: [
        .macro(name: "MacroImpl", dependencies: [
            .product(name: "MacroImplHelpers", package: "MacroImplHelpers"),
        ]),
        .target(name: "MacroDef", dependencies: ["MacroImpl"]),
        .executableTarget(name: "MacroClient", dependencies: ["MacroDef"]),
        .testTarget(name: "MinimalWebAssemblyMacroPackageTests", dependencies: ["MacroDef"]),
    ],
    swiftLanguageModes: [.v5]
)
