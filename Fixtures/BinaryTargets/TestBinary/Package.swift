// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "TestBinary",
    dependencies: [
    ],
    targets: [
        .target(name: "exe", dependencies: ["Library"]),
        .target(name: "Library", dependencies: ["SwiftFramework"]),
        .target(name: "cexe", dependencies: ["CLibrary"]),
        .target(name: "CLibrary", dependencies: ["StaticLibrary", "DynamicLibrary"]),
        .binaryTarget(name: "SwiftFramework", path: "SwiftFramework.xcframework"),
        .binaryTarget(name: "StaticLibrary", path: "StaticLibrary.xcframework"),
        .binaryTarget(name: "DynamicLibrary", path: "DynamicLibrary.xcframework"),
    ]
)
