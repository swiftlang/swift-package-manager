// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "AggregateLibraryTargets",
    products: [
        .executable(name: "Tool", targets: ["Tool"]),
    ],
    targets: [
        .target(name: "StaticMember"),
        .libraryTarget(
            name: "StaticAggregate",
            type: .static,
            dependencies: ["StaticMember"]
        ),
        .target(name: "DynamicMember"),
        .libraryTarget(
            name: "DynamicAggregate",
            type: .dynamic,
            dependencies: ["DynamicMember"]
        ),
        .target(name: "AutoMember"),
        .libraryTarget(
            name: "AutoAggregate",
            dependencies: ["AutoMember"]
        ),
        .executableTarget(
            name: "Tool",
            dependencies: ["StaticAggregate", "DynamicAggregate", "AutoAggregate"]
        ),
    ]
)
