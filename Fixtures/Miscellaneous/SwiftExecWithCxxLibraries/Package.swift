// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftExecWithCxxLibraries",
    targets: [
        .target(name: "Cxx1"),
        .target(name: "Cxx2"),
        .executableTarget(name: "tool", dependencies: ["Cxx1", "Cxx2"]),
    ],
    cxxLanguageStandard: .cxx17
)
