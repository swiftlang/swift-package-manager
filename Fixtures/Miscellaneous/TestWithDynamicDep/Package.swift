// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TestWithDynamicDep",
    dependencies: [
        .package(path: "MyDynDep"),
    ],
    targets: [
        .testTarget(
            name: "MyDynDepTests",
            dependencies: [.product(name: "MyDynDep", package: "MyDynDep")]
        ),
    ]
)
