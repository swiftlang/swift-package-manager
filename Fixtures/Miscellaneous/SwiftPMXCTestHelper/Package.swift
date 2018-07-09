// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "SwiftPMXCTestHelper",
    targets: [
        .target(name: "SwiftPMXCTestHelper", path: "Sources"),
        .testTarget(name: "SwiftPMXCTestHelperTests", dependencies: ["SwiftPMXCTestHelper"]),
        .testTarget(name: "ObjCTests"),
    ]
)

