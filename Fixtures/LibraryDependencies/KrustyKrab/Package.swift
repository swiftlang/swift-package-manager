// swift-tools-version:6.0
import PackageDescription

#if os(macOS)
let platform = "macOS-ARM64"
#elseif os(Linux)
let platform = "Ubuntu-24.04-X64"
#endif

let package = Package(name: "KrustyKrab",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .visionOS(.v2), .watchOS(.v11)],
    products: [
        .executable(name: "KrustyKrab", targets: ["KrustyKrab"]),
    ],
    dependencies: [
    ],
    targets: [
        .binaryTarget(
            name: "KrabbyPatty",
            path: "\(platform).artifactbundle"),

        .executableTarget(name: "KrustyKrab",
            dependencies: [
                .target(name: "KrabbyPatty"),
            ]),
    ]
)
