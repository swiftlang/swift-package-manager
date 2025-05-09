// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Foo",
    dependencies: [
        .package(path: "../Bar")
    ],
    targets: [
        .target(name: "foo", dependencies: [
            "FooLib",
            "cfoo",
            .product(name: "bar", package: "Bar")
        ]),
        .target(name: "cfoo"),
        .target(name: "FooLib", dependencies: [
            .product(name: "BarLib", package: "Bar"),
        ]),
    ],
    swiftLanguageVersions: [.v4_2, .v5]
)
