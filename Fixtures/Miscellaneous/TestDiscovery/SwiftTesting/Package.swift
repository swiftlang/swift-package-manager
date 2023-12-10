// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SwiftTesting",
    platforms: [
      .macOS(.v13), .iOS(.v16), .watchOS(.v9), .tvOS(.v16), .visionOS(.v1)
    ],
    dependencies: [
      .package(url: "https://github.com/apple/swift-testing.git", branch: "main"),
    ],
    targets: [
        .testTarget(
            name: "SwiftTestingTests",
            dependencies: [.product(name: "Testing", package: "swift-testing"),]
        ),
    ]
)
