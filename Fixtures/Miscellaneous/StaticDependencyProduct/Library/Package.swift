// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Library",
    products: [.library(name: "StaticLibrary", type: .static, targets: ["Library"])],
    targets: [.target(name: "Library")]
)
