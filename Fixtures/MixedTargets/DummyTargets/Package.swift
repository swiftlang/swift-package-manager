// swift-tools-version: 999.0
// FIXME(ncooke3): Update above version with the next version of SwiftPM.

import PackageDescription

let package = Package(
    name: "DummyTargets",
    dependencies: [
         .package(path: "../BasicMixedTargets")
    ],
    targets: [
        .executableTarget(
            name: "ClangExecutableDependsOnDynamicallyLinkedMixedTarget", 
            dependencies: [
                .product(
                    name: "DynamicallyLinkedBasicMixedTarget", 
                    package: "BasicMixedTargets"
                )
            ]
         ),
         .executableTarget(
             name: "ClangExecutableDependsOnStaticallyLinkedMixedTarget",
             dependencies: [
                .product(
                    name: "StaticallyLinkedBasicMixedTarget", 
                    package: "BasicMixedTargets"
                )
            ]
         ),
         .executableTarget(
             name: "SwiftExecutableDependsOnDynamicallyLinkedMixedTarget",
             dependencies: [
                .product(
                    name: "DynamicallyLinkedBasicMixedTarget", 
                    package: "BasicMixedTargets"
                )
             ]
         ),
         .executableTarget(
             name: "SwiftExecutableDependsOnStaticallyLinkedMixedTarget",
             dependencies: [
                .product(
                    name: "StaticallyLinkedBasicMixedTarget", 
                    package: "BasicMixedTargets"
                )
             ]
         )

    ]
)
