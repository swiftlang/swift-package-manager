// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "PackageWithNonc99NameModules",
    targets: [
        .target(name: "A-B", dependencies: ["B-C"]),
        .target(name: "B-C", dependencies: []),
        .target(name: "C D", dependencies: []),
    ]
)

