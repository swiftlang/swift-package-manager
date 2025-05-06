// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "IntegrationTests",
    platforms: [.macOS("13.0")],
    targets: [
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
                .product(name: "TSCTestSupport", package: "swift-tools-support-core"),
                "IntegrationTestSupport",
            ]),
        .target(
            name: "IntegrationTestSupport",
            dependencies: [
                .product(name: "TSCTestSupport", package: "swift-tools-support-core"),
            ]
        ),
    ]
)

import class Foundation.ProcessInfo

if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
    package.dependencies += [
        .package(url: "https://github.com/apple/swift-tools-support-core.git", .branch("main")),
    ]
} else {
    package.dependencies += [
        .package(name: "swift-tools-support-core", path: "../TSC"),
    ]
}
