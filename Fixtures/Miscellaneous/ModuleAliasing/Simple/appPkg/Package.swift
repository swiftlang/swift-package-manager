// swift-tools-version:999.0
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
        .package(url: "../GamePkg", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                "Utils",
                .product(name: "Utils",
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
        
