// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "AppPkg",
    dependencies: [
        .package(path: "../APkg"),
        .package(path: "../XPkg"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "A",
                         package: "APkg",
                         moduleAliases: ["FooUtils": "AFooUtils"]
                        ),
                .product(name: "X",
                         package: "XPkg",
                         moduleAliases: ["Utils": "XUtils", "FooUtils": "XFooUtils"]
                        )
            ]),
    ]
)

