// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "AppPkg",
    dependencies: [
        .package(path: "../UtilsPkg"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                "Utils",
                .product(name: "Lib",
                         package: "UtilsPkg",
                         moduleAliases: [
                            "Utils": "GameUtils",
                            "Lib": "GameLib",
                        ]),
            ],
            path: "./Sources/App"),
        .target(
                name: "Utils",
                dependencies: [],
                path: "./Sources/Utils"
            )
        ]
    )
        
