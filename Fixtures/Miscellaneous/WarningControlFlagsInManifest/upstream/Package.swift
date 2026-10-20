// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "upstream",
    products: [
        .library(name: "Upstream", targets: ["Upstream"]),
    ],
    targets: [
        .target(
            name: "Upstream",
            // Declare the SE-0480 warning-control settings in the manifest rather than
            // passing them on the command line. `treatAllWarnings` lowers to
            // `-warnings-as-errors` and `treatWarning` lowers to the two-token
            // `-Werror <group>` form in OTHER_SWIFT_FLAGS.
            swiftSettings: [
                .treatAllWarnings(as: .error),
                .treatWarning("DeprecatedDeclaration", as: .error),
            ]
        ),
    ]
)
