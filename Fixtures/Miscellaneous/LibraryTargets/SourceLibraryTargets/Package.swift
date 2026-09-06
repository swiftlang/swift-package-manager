// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "SourceLibraryTargets",
    products: [
        .executable(name: "Tool", targets: ["Tool"]),
    ],
    targets: [
        .target(name: "StaticLibCore"),
        .target(name: "DynamicLibCore"),
        .libraryTarget(
            name: "StaticLib",
            type: .static,
            dependencies: ["StaticLibCore"]
        ),
        .libraryTarget(
            name: "DynamicLib",
            type: .dynamic,
            dependencies: ["DynamicLibCore"]
        ),
        .libraryTarget(
            name: "AutoLib"
        ),
        .executableTarget(
            name: "Tool",
            dependencies: ["StaticLib", "DynamicLib", "AutoLib"]
        ),
    ]
)
