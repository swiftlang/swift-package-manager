// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "barPkg",
    products: [
        .library(name: "Bar", targets: ["Bar"]),
    ],
    targets: [
        .target(name: "Bar", dependencies: ["Baz"]),
        .target(name: "Baz"),
    ]
)
