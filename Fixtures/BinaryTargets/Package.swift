// swift-tools-version:999.0

import PackageDescription

let package = Package(
    name: "TestBinary",
    dependencies: [
    ],
    targets: [
        .target(name: "exe", dependencies: ["Library"]),
        .target(name: "Library", dependencies: ["MyFwk"]),
        .target(name: "cexe", dependencies: ["CLibrary"]),
        .target(name: "CLibrary", dependencies: ["StaticLibrary", "DynamicLibrary"]),
        .binaryTarget(name: "MyFwk", path: "MyFwk.xcframework"),
        .binaryTarget(name: "StaticLibrary", path: "StaticLibrary.xcframework"),
        .binaryTarget(name: "DynamicLibrary", path: "DynamicLibrary.xcframework"),
    ]
)
