// swift-tools-version: 6.5

import PackageDescription

let package = Package(
    name: "TestConfigurations",
    traits: [
        .default(enabledTraits: ["Foo"]),
        "Foo",
        "Bar",
    ],
    targets: [
        .target(
            name: "Library",
            swiftSettings: [
                .define("FOO", .when(traits: ["Foo"])),
                .define("BAR", .when(traits: ["Bar"])),
            ]
        ),
        .testTarget(
            name: "DefaultConfigurationTests",
            dependencies: ["Library"],
            traitConfigurations: [.default]
        ),
        .testTarget(
            name: "AllTraitsConfigurationTests",
            dependencies: ["Library"],
            traitConfigurations: [.enableAllTraits]
        ),
    ]
)
