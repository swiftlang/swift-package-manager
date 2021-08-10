// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "CLibrarySources",
    products: [
        .library(name: "Lib", targets: ["Bar"])
    ],
    targets: [
        .target(name: "Foo"),
        .target(name: "Bar", dependencies: ["Foo"])
    ]
)
