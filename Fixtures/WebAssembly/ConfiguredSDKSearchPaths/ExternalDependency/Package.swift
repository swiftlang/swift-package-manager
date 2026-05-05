// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Greeter",
    products: [
        .library(name: "Greeter", type: .static, targets: ["Greeter"]),
    ],
    targets: [
        .target(name: "Greeter"),
    ]
)
