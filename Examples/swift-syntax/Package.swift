// swift-tools-version:4.2

import PackageDescription

let package = Package(
  name: "SwiftSyntax",
  products: [
    .library(name: "SwiftSyntax", type: .dynamic, targets: ["SwiftSyntax"]),
    .packageExtension(name: "GYBExtension"),
  ],
  targets: [
    // GYB package extension.
    .packageExtension(name: "GYBExtension"),

    // The main SwiftSyntax target.
    .target(
        name: "SwiftSyntax",
        sources: [
            // Detect all the built-in sources.
            ".",

            // Build all gyb sources with the GYB build rule.
            .build("*.gyb", withBuildRule: "GYBRule"),
        ]
    ),

    .target(name: "lit-test-helper", dependencies: ["SwiftSyntax"]),
    .testTarget(name: "SwiftSyntaxTest", dependencies: ["SwiftSyntax"], exclude: ["Inputs"]),
  ]
)
