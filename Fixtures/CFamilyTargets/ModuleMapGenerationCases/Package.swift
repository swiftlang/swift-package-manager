// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "ModuleMapGenerationCases",
    targets: [
		.target(
            name: "Baz",
            dependencies: ["FlatInclude", "UmbrellaHeader", "UmbellaModuleNameInclude", "UmbrellaHeaderFlat"]),
		.target(
            name: "FlatInclude",
            dependencies: []),
		.target(
            name: "NoIncludeDir",
            dependencies: []),
		.target(
            name: "UmbellaModuleNameInclude",
            dependencies: []),
		.target(
            name: "UmbrellaHeader",
            dependencies: []),
		.target(
            name: "UmbrellaHeaderFlat",
            dependencies: []),
    ]
)
