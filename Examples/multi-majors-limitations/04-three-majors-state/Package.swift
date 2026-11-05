// swift-tools-version: 5.9
import PackageDescription

// Three libraries, three different majors of Shared, and the root has no direct dependency on Shared.
// This is the "happy path" scaled up from the existing prototype example: does resolution produce three
// buckets, and is Shared's process-global state (SharedSupport.log) really separate per major?
//
// Prediction: sharedMajor is 1/2/3, and each registerAndDump() returns only its own library's entry.
// If a log ever contains entries from another library, two majors got merged into one module.
let package = Package(
    name: "three-majors-state",
    dependencies: [
        .package(path: "../libs/LibOne"),
        .package(path: "../libs/LibTwo"),
        .package(path: "../libs/LibThree"),
    ],
    targets: [
        .executableTarget(
            name: "three",
            dependencies: [
                .product(name: "LibOne", package: "LibOne"),
                .product(name: "LibTwo", package: "LibTwo"),
                .product(name: "LibThree", package: "LibThree"),
            ]
        ),
    ]
)
