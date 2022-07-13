// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "AppPkg",
    dependencies: [
        .package(path: "../Apkg"),
        .package(path: "../Bpkg"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Utils",
                         package: "Apkg",
                         moduleAliases: ["Utils": "AUtils"]
                        ),
                .product(name: "Utils",
                         package: "Bpkg",
                         moduleAliases: ["Utils": "BUtils"]
                        )
            ]),
    ]
)

