// swift-tools-version:999.0
import PackageDescription

let package = Package(
    name: "AtMainSupport",
    products: [
        .executable(name: "ClangExec", targets: ["ClangExec"]),
        .executable(name: "SwiftExec", targets: ["SwiftExec"]),
    ],
    targets: [
        .executableTarget(name: "ClangExec"),
        .executableTarget(name: "SwiftExec"),
    ]
)