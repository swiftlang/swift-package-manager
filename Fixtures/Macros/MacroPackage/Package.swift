// swift-tools-version: 999.0
import PackageDescription
import CompilerPluginSupport

let settings: [SwiftSetting] = [
    .enableExperimentalFeature("Macros"),
    .unsafeFlags(["-Xfrontend", "-dump-macro-expansions"])
]

let package = Package(
	name: "MacroPackage",
	platforms: [
		.macOS(.v10_15),
	],
	targets: [
		.macro(name: "MacroImpl"),
		.target(name: "MacroDef", dependencies: ["MacroImpl"], swiftSettings: settings),
		.executableTarget(name: "MacroClient", dependencies: ["MacroDef"], swiftSettings: settings),
	]
)
