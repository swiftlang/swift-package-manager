// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LibraryWithTestAndDep",
    dependencies: [
        .package(path: "MyDep"),
    ],
    targets: [
        .target(
            name: "MyLib",
            dependencies: [.product(name: "MyDep", package: "MyDep")]
        ),
        .testTarget(
            name: "MyLibTests",
            dependencies: ["MyLib"]
        ),
    ]
)
