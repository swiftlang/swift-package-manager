// swift-tools-version:6.0
import PackageDescription

let package = Package(name: "KrustyKrab",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .visionOS(.v2), .watchOS(.v11)],
    products: [
        .executable(name: "KrustyKrab", targets: ["KrustyKrab"]),
    ],
    dependencies: [
    ],
    targets: [
        .binaryTarget(name: "KrabbyPatty", path: "main.artifactbundle"),

        .executableTarget(name: "KrustyKrab",
            dependencies: [
                .target(name: "KrabbyPatty"),
            ]
        ),
    ]
)
