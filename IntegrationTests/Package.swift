// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "IntegrationTests",
    targets: [
        .testTarget(name: "IntegrationTests", dependencies: [
            "SwiftToolsSupport-auto",
            "TSCTestSupport"
        ]),
    ]
)

import class Foundation.ProcessInfo

if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
    package.dependencies += [
        .package(url: "https://github.com/apple/swift-tools-support-core.git", .branch("main")),
    ]
} else {
    package.dependencies += [
        .package(path: "../TSC"),
    ]
}
