// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "MixedTargets",
    products: [
        .library(
            name: "BasicMixedTarget",
            targets: ["BasicMixedTarget"]
        ),
        .library(
            name: "StaticallyLinkedBasicMixedTarget",
            type: .static,
            targets: ["BasicMixedTarget"]
        ),
        .library(
            name: "DynamicallyLinkedBasicMixedTarget",
            type: .dynamic,
            targets: ["BasicMixedTarget"]
        )
    ],
    dependencies: [],
    targets: [
        // MARK: - BasicMixedTarget
        .target(
            name: "BasicMixedTarget"
        ),
        .testTarget(
            name: "BasicMixedTargetTests",
            dependencies: ["BasicMixedTarget"]
        ),

        // MARK: - MixedTargetWithResources
        .target(
            name: "MixedTargetWithResources",
            resources: [
                .process("foo.txt")
            ]
        ),
        .testTarget(
            name: "MixedTargetWithResourcesTests",
            dependencies: ["MixedTargetWithResources"]
        ),

        // MARK: - MixedTargetWithCustomModuleMap
        // TODO(ncooke3): Play around and try to break this target with a more
        // complex module map.
        .target(
            name: "MixedTargetWithCustomModuleMap"
        ),

        // MARK: - MixedTargetWithCustomModuleMapAndResources
        .target(
            name: "MixedTargetWithCustomModuleMapAndResources",
            resources: [
                .process("foo.txt")
            ]
        ),

        // MARK: - MixedTargetWithC++
        .target(
            name: "MixedTargetWithCXX"
        ),
        .testTarget(
            name: "MixedTargetWithCXXTests",
            dependencies: ["MixedTargetWithCXX"]
        ),

        // MARK: MixedTargetWithCXXAndCustomModuleMap
        .target(
            name: "MixedTargetWithCXXAndCustomModuleMap"
        ),

        // MARK: - MixedTargetWithC
        .target(
            name: "MixedTargetWithC"
        ),
        .testTarget(
            name: "MixedTargetWithCTests",
            dependencies: ["MixedTargetWithC"]
        ),

        // MARK: - MixedTargetWithNonPublicHeaders
        .target(
            name: "MixedTargetWithNonPublicHeaders"
        ),
        // This test target should fail to build. See
        // `testNonPublicHeadersAreNotVisibleFromOutsideOfTarget`.
        .testTarget(
            name: "MixedTargetWithNonPublicHeadersTests",
            dependencies: ["MixedTargetWithNonPublicHeaders"]
        ),

        // MARK: - MixedTargetWithCustomPaths
        .target(
            name: "MixedTargetWithCustomPaths",
            path: "MixedTargetWithCustomPaths/Sources",
            publicHeadersPath: "Public",
            cSettings: [
                .headerSearchPath("../../")
            ]
        ),

        // MARK: - MixedTargetWithNestedPublicHeaders
        .target(
            name: "MixedTargetWithNestedPublicHeaders",
            publicHeadersPath: "Blah/Public"
        ),

        // MARK: - MixedTargetWithNestedPublicHeadersAndCustomModuleMap
        .target(
            name: "MixedTargetWithNestedPublicHeadersAndCustomModuleMap",
            publicHeadersPath: "Blah/Public"
        ),

        // MARK: - MixedTargetWithNoPublicObjectiveCHeaders.
       .target(
           name: "MixedTargetWithNoPublicObjectiveCHeaders"
       ),
        .testTarget(
            name: "MixedTargetWithNoPublicObjectiveCHeadersTests",
            dependencies: ["MixedTargetWithNoPublicObjectiveCHeaders"]
        ),

        // MARK: - MixedTestTargetWithSharedTestUtilities
        .testTarget(
            name: "MixedTestTargetWithSharedUtilitiesTests"
        ),

        // MARK: - PrivateHeadersCanBeTestedViaHeaderSearchPathsTests
        .testTarget(
            name: "PrivateHeadersCanBeTestedViaHeaderSearchPathsTests",
            dependencies: ["MixedTargetWithNonPublicHeaders"],
            cSettings: [
                // Adding a header search path at the root of the package will
                // enable the Objective-C tests to import private headers.
                .headerSearchPath("../../")
            ]
        ),

        // MARK: - MixedTargetsPublicHeadersAreIncludedInHeaderSearchPathsForObjcSource
        .target(
            name: "MixedTargetsPublicHeadersAreIncludedInHeaderSearchPathsForObjcSource"
        ),

        // MARK: - Targets for testing the integration of a mixed target
        .target(
            name: "ClangTargetDependsOnMixedTarget",
            dependencies: ["BasicMixedTarget"]
         ),
         .target(
             name: "SwiftTargetDependsOnMixedTarget",
             dependencies: ["BasicMixedTarget"]
         ),
         .target(
             name: "MixedTargetDependsOnMixedTarget",
             dependencies: ["BasicMixedTarget"]
         ),
         .target(
             name: "MixedTargetDependsOnClangTarget",
             dependencies: ["ClangTarget"]
         ),
         .target(
             name: "MixedTargetDependsOnSwiftTarget",
             dependencies: ["SwiftTarget"]
         ),
         // The below two targets are used for testing the above targets.
         .target(name: "SwiftTarget"),
         .target(name: "ClangTarget")

    ]
)
