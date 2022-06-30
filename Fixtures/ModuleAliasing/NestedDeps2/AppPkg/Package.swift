// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "AppPkg",
    dependencies: [
        .package(path: "../Apkg"),
        .package(path: "../Xpkg"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "A",
                         package: "Apkg"
                        ),
                .product(name: "Utils",
                         package: "Xpkg",
                         moduleAliases: ["Utils": "XUtils"]
                        ),
            ]),
        ]
)

