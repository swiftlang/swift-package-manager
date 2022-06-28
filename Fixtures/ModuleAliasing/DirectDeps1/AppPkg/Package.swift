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
                .product(name: "Utils",
                         package: "UtilsPkg",
                         moduleAliases: ["Utils": "GameUtils"])
            ],
            path: "./Sources/App"),
        .target(
                name: "Utils",
                dependencies: [],
                path: "./Sources/Utils"
            )
        ]
    )
        
