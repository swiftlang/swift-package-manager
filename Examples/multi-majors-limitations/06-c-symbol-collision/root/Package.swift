// swift-tools-version: 5.9
import PackageDescription

// SharedC 1.x and 2.x both define the C symbol `shared_c_version`. Module aliasing is a Swift compiler
// feature (-module-alias); it cannot rename symbols inside compiled C objects.
//
// Prediction: the Swift side compiles, and the failure shows up at link time as
// "duplicate symbol '_shared_c_version'". It is also possible the build fails earlier because the C
// module itself collides, which would be a different (and earlier) limitation worth noting.
// validateAndApplyAliases warns about non-Swift sources for aliased modules, so check for that too.
let package = Package(
    name: "c-symbol-collision",
    dependencies: [
        .package(path: "../liba"),
        .package(path: "../libb"),
    ],
    targets: [
        .executableTarget(
            name: "root",
            dependencies: [
                .product(name: "LibA", package: "liba"),
                .product(name: "LibB", package: "libb"),
            ]
        ),
    ]
)
