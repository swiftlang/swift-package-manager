// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "some-dep",
    products: [
        .library(name: "SomeDep", targets: ["SomeDep"]),
    ],
    targets: [
        .target(name: "SomeDep"),
    ],
)
