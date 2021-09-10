// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Foo",
    products: [
        .library(name: "FooLib", type: .static, targets: ["FooLib"]),
    ],
    dependencies: [
        .package(path: "../Bar")
    ],
    targets: [
        .target(name: "FooLib", dependencies: ["CFooLib"]),
        .target(name: "CFooLib", dependencies: [
            .product(name: "BarLib", package: "Bar"),
        ]),
    ],
    swiftLanguageVersions: [.v4_2, .v5]
)
