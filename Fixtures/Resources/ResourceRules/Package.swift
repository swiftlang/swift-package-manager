// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ResourceRules",
    targets: [
        .executableTarget(name: "ResourceRules", resources: [
		.copy("CopiedAssets.xcassets"),
		.process("ProcessedAssets.xcassets")
	]),
    ]
)
