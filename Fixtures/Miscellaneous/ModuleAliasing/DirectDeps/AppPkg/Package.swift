// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "AppPkg",
    platforms: [
        .macOS(.v10_12),
        .iOS(.v10),
        .tvOS(.v11),
        .watchOS(.v5)
    ],
    dependencies: [
        .package(path: "../GamePkg"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                "Utils",
                .product(name: "UtilsProd",
                         package: "GamePkg",
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
