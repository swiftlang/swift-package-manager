// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "ExecutableNew",
    targets: [
        .target(name: "ExecutableSwift"),
        .target(name: "ExecutableC"),
        .target(name: "ExecutableCxx"),
    ]
)
