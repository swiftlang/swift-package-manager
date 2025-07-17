// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "AppPkg",
    dependencies: [
        .package(path: "../XPkg"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "X",
                         package: "XPkg",
                         moduleAliases: ["Utils": "XUtils", "X": "XNew"]
                        )
            ]),
    ]
)

