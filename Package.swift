// swift-tools-version:5.5

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageDescription
import class Foundation.ProcessInfo


/** SwiftPMDataModel is the subset of SwiftPM product that includes just its data model.
This allows some clients (such as IDEs) that use SwiftPM's data model but not its build system
to not have to depend on SwiftDriver, SwiftLLBuild, etc. We should probably have better names here,
though that could break some clients.
*/
let swiftPMDataModelProduct = (
    name: "SwiftPMDataModel",
    targets: [
        "PackageCollections",
        "PackageCollectionsModel",
        "PackageGraph",
        "PackageLoading",
        "PackageModel",
        "SourceControl",
        "Workspace",
    ]
)

/** The `libSwiftPM` set of interfaces to programmatically work with Swift
 packages.  `libSwiftPM` includes all of the SwiftPM code except the
 command line tools, while `libSwiftPMDataModel` includes only the data model.

 NOTE: This API is *unstable* and may change at any time.
*/
let swiftPMProduct = (
    name: "SwiftPM",
    targets: swiftPMDataModelProduct.targets + [
        "Build",
        "LLBuildManifest",
        "SPMLLBuild",
    ]
)

/** An array of products which have two versions listed: one dynamically linked, the other with the
automatic linking type with `-auto` suffix appended to product's name.
*/
let autoProducts = [swiftPMProduct, swiftPMDataModelProduct]

let useSwiftCryptoV2 = ProcessInfo.processInfo.environment["SWIFTPM_USE_SWIFT_CRYPTO_V2"] != nil
let minimumCryptoVersion: Version = useSwiftCryptoV2 ? "2.1.0" : "1.1.7"
var swiftSettings: [SwiftSetting] = []
if useSwiftCryptoV2 {
    swiftSettings.append(.define("CRYPTO_v2"))
}

var packageCollectionsSigningTargets = [Target]()
var packageCollectionsSigningDeps: [Target.Dependency] = [
    "Basics",
    .product(name: "Crypto", package: "swift-crypto"),
    "PackageCollectionsModel",
]
// swift-crypto's Crypto module depends on CCryptoBoringSSL on these platforms only
#if os(Linux) || os(Windows) || os(Android)
packageCollectionsSigningTargets.append(
    .target(
        /** Package collections signing C lib */
        name: "PackageCollectionsSigningLibc",
        dependencies: [
            .product(name: "Crypto", package: "swift-crypto"), // for CCryptoBoringSSL
        ],
        exclude: ["CMakeLists.txt"],
        cSettings: [
            .define("WIN32_LEAN_AND_MEAN"),
        ]
    )
)
packageCollectionsSigningDeps.append("PackageCollectionsSigningLibc")
#endif
// Define PackageCollectionsSigning target always
packageCollectionsSigningTargets.append(
    .target(
         /** Package collections signing */
         name: "PackageCollectionsSigning",
         dependencies: packageCollectionsSigningDeps,
         exclude: ["CMakeLists.txt"],
         swiftSettings: swiftSettings
    )
)

let package = Package(
    name: "SwiftPM",
    platforms: [
        .macOS("10.15.4"),
        .iOS("13.4")
    ],
    products:
        autoProducts.flatMap {
          [
            .library(
                name: $0.name,
                type: .dynamic,
                targets: $0.targets
            ),
            .library(
                name: "\($0.name)-auto",
                targets: $0.targets
            )
          ]
        } + [
        .library(
            name: "XCBuildSupport",
            targets: ["XCBuildSupport"]
        ),
        .library(
            name: "PackageDescription",
            type: .dynamic,
            targets: ["PackageDescription"]
        ),
        .library(
            name: "PackagePlugin",
            type: .dynamic,
            targets: ["PackagePlugin"]
        ),
        .library(
            name: "PackageCollectionsModel",
            targets: ["PackageCollectionsModel"]
        ),
        .library(
            name: "SwiftPMPackageCollections",
            targets: [
                "PackageCollections",
                "PackageCollectionsModel",
                "PackageCollectionsSigning",
                "PackageModel",
            ]
        ),
    ],
    targets: packageCollectionsSigningTargets + [
        // The `PackageDescription` target provides the API that is available
        // to `Package.swift` manifests. Here we build a debug version of the
        // library; the bootstrap scripts build the deployable version.
        .target(
            name: "PackageDescription",
            exclude: ["CMakeLists.txt"],
            swiftSettings: [
                .unsafeFlags(["-package-description-version", "999.0"]),
                .unsafeFlags(["-enable-library-evolution"], .when(platforms: [.macOS]))
            ]
        ),

        // The `PackagePlugin` target provides the API that is available to
        // plugin scripts. Here we build a debug version of the library; the
        // bootstrap scripts build the deployable version.
        .target(
            name: "PackagePlugin",
            exclude: ["CMakeLists.txt"],
            swiftSettings: [
                .unsafeFlags(["-package-description-version", "999.0"]),
                .unsafeFlags(["-enable-library-evolution"], .when(platforms: [.macOS]))
            ]
        ),

        // MARK: SwiftPM specific support libraries

        .systemLibrary(name: "SPMSQLite3", pkgConfig: "sqlite3"),

        .target(
            name: "Basics",
            dependencies: [
                "SPMSQLite3",
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            exclude: ["CMakeLists.txt"]
        ),

        .target(
            /** The llbuild manifest model */
            name: "LLBuildManifest",
            dependencies: ["Basics"],
            exclude: ["CMakeLists.txt"]
        ),

        .target(
            /** Package registry support */
            name: "PackageRegistry",
            dependencies: [
                "Basics",
                "PackageFingerprint",
                "PackageLoading",
                "PackageModel"
            ],
            exclude: ["CMakeLists.txt"]
        ),

        .target(
            /** Source control operations */
            name: "SourceControl",
            dependencies: [
                "Basics",
                "PackageModel"
            ],
            exclude: ["CMakeLists.txt"]
        ),

        .target(
            /** Shim for llbuild library */
            name: "SPMLLBuild",
            dependencies: ["Basics"],
            exclude: ["CMakeLists.txt"]
        ),

        // MARK: Project Model

        .target(
            /** Primitive Package model objects */
            name: "PackageModel",
            dependencies: ["Basics"],
            exclude: ["CMakeLists.txt", "README.md"]
        ),

        .target(
            /** Package model conventions and loading support */
            name: "PackageLoading",
            dependencies: [
                "Basics",
                "PackageModel"
            ],
            exclude: ["CMakeLists.txt", "README.md"]
        ),

        // MARK: Package Dependency Resolution

        .target(
            /** Data structures and support for complete package graphs */
            name: "PackageGraph",
            dependencies: [
                "Basics",
                "PackageLoading",
                "PackageModel",
                "PackageRegistry",
                "SourceControl"
            ],
            exclude: ["CMakeLists.txt", "README.md"]
        ),

        // MARK: Package Collections

        .target(
            /** Package collections models */
            name: "PackageCollectionsModel",
            dependencies: [],
            exclude: [
                "CMakeLists.txt",
                "Formats/v1.md"
            ]
        ),

        .target(
            /** Data structures and support for package collections */
            name: "PackageCollections",
            dependencies: [
                "Basics",
                "PackageCollectionsModel",
                "PackageCollectionsSigning",
                "PackageModel",
                "SourceControl",
            ],
            exclude: ["CMakeLists.txt"]
        ),

        .target(
            name: "PackageFingerprint",
            dependencies: [
                "Basics",
                "PackageModel",
            ],
            exclude: ["CMakeLists.txt"]
        ),

        // MARK: Package Manager Functionality

        .target(
            /** Builds Modules and Products */
            name: "SPMBuildCore",
            dependencies: [
                "Basics",
                "PackageGraph"
            ],
            exclude: ["CMakeLists.txt"]
        ),
        .target(
            /** Builds Modules and Products */
            name: "Build",
            dependencies: [
                "Basics",
                "LLBuildManifest",
                "PackageGraph",
                "SPMBuildCore",
                "SPMLLBuild",
                .product(name: "SwiftDriver", package: "swift-driver"),
            ],
            exclude: ["CMakeLists.txt"]
        ),
        .target(
            /** Support for building using Xcode's build system */
            name: "XCBuildSupport",
            dependencies: ["SPMBuildCore", "PackageGraph"],
            exclude: ["CMakeLists.txt"]
        ),
        .target(
            /** High level functionality */
            name: "Workspace",
            dependencies: [
                "Basics",
                "PackageFingerprint",
                "PackageGraph",
                "PackageModel",
                "SourceControl",
                "SPMBuildCore",
            ],
            exclude: ["CMakeLists.txt"]
        ),

        // MARK: Commands

        .target(
            /** High-level commands */
            name: "Commands",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Basics",
                "Build",
                "PackageCollections",
                "PackageFingerprint",
                "PackageGraph",
                "SourceControl",
                "Workspace",
                "XCBuildSupport",
            ],
            exclude: ["CMakeLists.txt", "README.md"]
        ),
        .executableTarget(
            /** The main executable provided by SwiftPM */
            name: "swift-package",
            dependencies: ["Basics", "Commands"],
            exclude: ["CMakeLists.txt"]
        ),
        .executableTarget(
            /** Builds packages */
            name: "swift-build",
            dependencies: ["Commands"],
            exclude: ["CMakeLists.txt"]
        ),
        .executableTarget(
            /** Runs package tests */
            name: "swift-test",
            dependencies: ["Commands"],
            exclude: ["CMakeLists.txt"]
        ),
        .executableTarget(
            /** Runs an executable product */
            name: "swift-run",
            dependencies: ["Commands"],
            exclude: ["CMakeLists.txt"]
        ),
        .executableTarget(
            /** Interacts with package collections */
            name: "swift-package-collection",
            dependencies: ["Commands"],
            exclude: ["CMakeLists.txt"]
        ),
        .executableTarget(
            /** Interact with package registry */
            name: "swift-package-registry",
            dependencies: ["Commands"],
            exclude: ["CMakeLists.txt"]
        ),
        .executableTarget(
            /** Shim tool to find test names on OS X */
            name: "swiftpm-xctest-helper",
            dependencies: [],
            exclude: ["CMakeLists.txt"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../../lib/swift/macosx"], .when(platforms: [.macOS])),
            ]),

        // MARK: Additional Test Dependencies

        .target(
            /** SwiftPM test support library */
            name: "SPMTestSupport",
            dependencies: [
                "Basics",
                "PackageFingerprint",
                "PackageGraph",
                "PackageLoading",
                "PackageRegistry",
                "SourceControl",
                .product(name: "TSCTestSupport", package: "swift-tools-support-core"),
                "Workspace",
                "XCBuildSupport",
            ]
        ),

        .target(
            /** Test for thread-santizer. */
            name: "tsan_utils",
            dependencies: []),

        // MARK: SwiftPM tests

        .testTarget(
            name: "BasicsTests",
            dependencies: ["Basics", "SPMTestSupport", "tsan_utils"],
            exclude: [
                "Inputs/archive.zip",
                "Inputs/invalid_archive.zip",
            ]
        ),
        .testTarget(
            name: "BuildTests",
            dependencies: ["Build", "SPMTestSupport"]
        ),
        .testTarget(
            name: "CommandsTests",
            dependencies: [
                "swift-build",
                "swift-package",
                "swift-test",
                "swift-run",
                "Commands",
                "Workspace",
                "SPMTestSupport",
                "Build",
                "SourceControl"
            ]
        ),
        .testTarget(
            name: "WorkspaceTests",
            dependencies: ["Workspace", "SPMTestSupport"]
        ),
        .testTarget(
            name: "FunctionalTests",
            dependencies: [
                "swift-build",
                "swift-package",
                "swift-test",
                "PackageModel",
                "SPMTestSupport"
            ]
        ),
        .testTarget(
            name: "FunctionalPerformanceTests",
            dependencies: [
                "swift-build",
                "swift-package",
                "swift-test",
                "SPMTestSupport"
            ]
        ),
        .testTarget(
            name: "PackageDescriptionTests",
            dependencies: ["PackageDescription"]
        ),
        .testTarget(
            name: "SPMBuildCoreTests",
            dependencies: ["SPMBuildCore", "SPMTestSupport"]
        ),
        .testTarget(
            name: "PackageLoadingTests",
            dependencies: ["PackageLoading", "SPMTestSupport"],
            exclude: ["Inputs", "pkgconfigInputs"]
        ),
        .testTarget(
            name: "PackageLoadingPerformanceTests",
            dependencies: ["PackageLoading", "SPMTestSupport"]
        ),
        .testTarget(
            name: "PackageModelTests",
            dependencies: ["PackageModel", "SPMTestSupport"]
        ),
        .testTarget(
            name: "PackageGraphTests",
            dependencies: ["PackageGraph", "SPMTestSupport"]
        ),
        .testTarget(
            name: "PackageGraphPerformanceTests",
            dependencies: ["PackageGraph", "SPMTestSupport"],
            exclude: [
                "Inputs/PerfectHTTPServer.json",
                "Inputs/ZewoHTTPServer.json",
                "Inputs/SourceKitten.json",
                "Inputs/kitura.json",
            ]
        ),
        .testTarget(
            name: "PackageCollectionsModelTests",
            dependencies: ["PackageCollectionsModel"]
        ),
        .testTarget(
            name: "PackageCollectionsSigningTests",
            dependencies: ["PackageCollectionsSigning", "SPMTestSupport"]
        ),
        .testTarget(
            name: "PackageCollectionsTests",
            dependencies: ["PackageCollections", "SPMTestSupport", "tsan_utils"]
        ),
        .testTarget(
            name: "PackageFingerprintTests",
            dependencies: ["PackageFingerprint", "SPMTestSupport"]
        ),
        .testTarget(
            name: "PackagePluginAPITests",
            dependencies: ["PackagePlugin", "SPMTestSupport"]
        ),
        .testTarget(
            name: "PackageRegistryTests",
            dependencies: ["SPMTestSupport", "PackageRegistry"]
        ),
        .testTarget(
            name: "SourceControlTests",
            dependencies: ["SourceControl", "SPMTestSupport"],
            exclude: ["Inputs/TestRepo.tgz"]
        ),
        .testTarget(
            name: "XCBuildSupportTests",
            dependencies: ["XCBuildSupport", "SPMTestSupport"],
            exclude: ["Inputs/Foo.pc"]
        ),

        // Examples (These are built to ensure they stay up to date with the API.)
        .executableTarget(
            name: "package-info",
            dependencies: ["Workspace"],
            path: "Examples/package-info/Sources/package-info"
        )
    ],
    swiftLanguageVersions: [.v5]
)

// Add package dependency on llbuild when not bootstrapping.
//
// When bootstrapping SwiftPM, we can't use llbuild as a package dependency it
// will provided by whatever build system (SwiftCI, bootstrap script) is driving
// the build process. So, we only add these dependencies if SwiftPM is being
// built directly using SwiftPM. It is a bit unfortunate that we've add the
// package dependency like this but there is no other good way of expressing
// this right now.

/// When not using local dependencies, the branch to use for llbuild and TSC repositories.
let relatedDependenciesBranch = "main"

if ProcessInfo.processInfo.environment["SWIFTPM_LLBUILD_FWK"] == nil {
    if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
        package.dependencies += [
            .package(url: "https://github.com/apple/swift-llbuild.git", .branch(relatedDependenciesBranch)),
        ]
    } else {
        // In Swift CI, use a local path to llbuild to interoperate with tools
        // like `update-checkout`, which control the sources externally.
        package.dependencies += [
            .package(name: "swift-llbuild", path: "../llbuild"),
        ]
    }
    package.targets.first(where: { $0.name == "SPMLLBuild" })!.dependencies += [.product(name: "llbuildSwift", package: "swift-llbuild")]
}

if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
    package.dependencies += [
        .package(url: "https://github.com/apple/swift-tools-support-core.git", .branch(relatedDependenciesBranch)),
        // The 'swift-argument-parser' version declared here must match that
        // used by 'swift-driver' and 'sourcekit-lsp'. Please coordinate
        // dependency version changes here with those projects.
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.0.3")),
        .package(url: "https://github.com/apple/swift-driver.git", .branch(relatedDependenciesBranch)),
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMinor(from: minimumCryptoVersion)),
        .package(url: "https://github.com/apple/swift-system.git", .upToNextMinor(from: "1.1.1")),
        .package(url: "https://github.com/apple/swift-collections.git", .upToNextMinor(from: "1.0.1")),
    ]
} else {
    package.dependencies += [
        .package(path: "../swift-tools-support-core"),
        .package(path: "../swift-argument-parser"),
        .package(path: "../swift-driver"),
        .package(path: "../swift-crypto"),
        .package(path: "../swift-system"),
        .package(path: "../swift-collections"),
    ]
}
