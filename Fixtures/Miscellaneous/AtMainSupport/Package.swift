// swift-tools-version:5.4
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