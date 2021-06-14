// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "AtMainSupport",
    products: [
        .executable(name: "ClangExecSingleFile", targets: ["ClangExecSingleFile"]),
        .executable(name: "SwiftExecSingleFile", targets: ["SwiftExecSingleFile"]),
        .executable(name: "SwiftExecMultiFile", targets: ["SwiftExecMultiFile"]),
    ],
    targets: [
        .executableTarget(name: "ClangExecSingleFile"),
        .executableTarget(name: "SwiftExecSingleFile"),
        .executableTarget(name: "SwiftExecMultiFile"),
    ]
)
