// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "app",
    products: [
        .executable(name: "app", targets: ["app"])
    ],
    targets: [
        .executableTarget(
          name: "app",
          path: "./"
        )
    ]
)
