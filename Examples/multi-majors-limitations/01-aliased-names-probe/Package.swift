// swift-tools-version: 5.9
import PackageDescription

// THE HEADLINE QUESTION: can one package use BOTH majors of Shared through their aliased names
// (Shared_v1 and Shared_v2)?
//
// This root depends on Shared directly with a range that spans two majors, and also uses LibOne
// (Shared 1.x) and LibTwo (Shared 2.x). Both majors get resolved, but the root is a single consumer,
// and the prototype hands each consumer exactly one bucket: majorVersionIdentity /
// resolvedPackage(for:consumer:) pick the HIGHEST major that is both declared and resolved.
//
// Prediction: root links Shared@2 only. `canImport(Shared_v2)` is true, `canImport(Shared_v1)` is
// false, so the root has no way to name Shared 1.x types even though LibOne exposes them.
let package = Package(
    name: "aliased-names-probe",
    dependencies: [
        .package(url: "file:///tmp/multi-major-fixtures/Shared", "1.0.0"..<"3.0.0"),
        .package(path: "../libs/LibOne"),
        .package(path: "../libs/LibTwo"),
    ],
    targets: [
        .executableTarget(
            name: "probe",
            dependencies: [
                .product(name: "Shared", package: "Shared"),
                .product(name: "LibOne", package: "LibOne"),
                .product(name: "LibTwo", package: "LibTwo"),
            ]
        ),
    ]
)
