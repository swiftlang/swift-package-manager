// swift-tools-version: 5.9
import PackageDescription

// The obvious way for ONE package to ask for BOTH majors is to declare the dependency twice, once per
// major. This example does exactly that.
//
// Prediction: this does not get as far as resolution. Both declarations have the identity "shared", so
// manifest validation rejects the package with a duplicate-dependency error, and there is no way for a
// single package to name two buckets of the same repository. If instead it resolves, look at which
// bucket the product reference binds to (see the [MultiMajor][4-Aliasing] log lines).
let package = Package(
    name: "duplicate-declarations",
    dependencies: [
        .package(url: "file:///tmp/multi-major-fixtures/Shared", "1.0.0"..<"2.0.0"),
        .package(url: "file:///tmp/multi-major-fixtures/Shared", "2.0.0"..<"3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "dup",
            dependencies: [.product(name: "Shared", package: "Shared")]
        ),
    ]
)
