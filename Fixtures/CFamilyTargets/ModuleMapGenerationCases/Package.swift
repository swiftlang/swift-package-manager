// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "ModuleMapGenerationCases",
    targets: [
		.target(
            name: "Baz",
            dependencies: ["CustomModuleMap", "FlatInclude", "NonModuleDirectoryInclude", "UmbrellaHeader", "UmbrellaDirectoryInclude", "UmbrellaHeaderFlat"]),
        .target(
            name: "CustomModuleMap",
            dependencies: []),
		.target(
            name: "FlatInclude",
            dependencies: []),
		.target(
            name: "NoIncludeDir",
            dependencies: []),
		.target(
            name: "NonModuleDirectoryInclude",
            dependencies: []),
		.target(
            name: "UmbrellaDirectoryInclude",
            dependencies: []),
		.target(
            name: "UmbrellaHeader",
            dependencies: []),
		.target(
            name: "UmbrellaHeaderFlat",
            dependencies: []),
    ]
)
