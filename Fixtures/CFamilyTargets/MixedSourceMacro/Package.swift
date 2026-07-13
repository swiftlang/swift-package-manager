// swift-tools-version: 6.4;(experimentalMultiLang)
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "MixedSourceMacro",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .macro(name: "MacroImpl"),
        .target(name: "MacroDef", dependencies: ["MacroImpl"]),
        .executableTarget(name: "MacroClient", dependencies: ["MacroDef"]),
    ],
    swiftLanguageModes: [.v5]
)
