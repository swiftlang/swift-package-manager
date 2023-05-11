// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "appPkg",
    dependencies: [
        .package(url: "../fooPkg", from: "1.0.0"),
        .package(url: "../barPkg", from: "1.0.0")
    ],
    targets: [
        .executableTarget(name: "exe", dependencies: ["App"]),
        .target(name: "App",
                dependencies: [
                    .product(name: "Foo", package: "fooPkg"),
                    .product(name: "Bar", package: "barPkg"),
                ])
    ]
)
