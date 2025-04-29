// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Foo",
    dependencies: [
        .package(path: "../Bar")
    ],
    targets: [
        .target(name: "FooLib", dependencies: [
            .product(name: "BarLib", package: "Bar"),
        ]),
        .testTarget(name: "FooTests", dependencies: ["FooLib"]),
        .testTarget(name: "CFooTests", dependencies: ["FooLib"]),
    ],
    swiftLanguageVersions: [.v4_2, .v5]
)
