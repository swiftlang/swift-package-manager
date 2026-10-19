// swift-tools-version: 6.5

import PackageDescription

let package = Package(
    name: "TestConfigurationsFailing",
    traits: [
        .default(enabledTraits: ["Foo"]),
        "Foo",
        "Bar",
    ],
    targets: [
        .target(name: "Library"),
        .testTarget(
            name: "PassingTests",
            dependencies: ["Library"],
            traitConfigurations: [.default]
        ),
        .testTarget(
            name: "FailingTests",
            dependencies: ["Library"],
            traitConfigurations: [.enableAllTraits]
        ),
    ]
)
