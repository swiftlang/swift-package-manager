// swift-tools-version:6.1

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class Foundation.ProcessInfo
import PackageDescription

// When building the toolchain on the CI for ELF platforms, remove the CI's
// stdlib absolute runpath and add ELF's $ORIGIN relative paths before installing.
let swiftpmLinkSettings: [LinkerSetting]
let packageLibraryLinkSettings: [LinkerSetting]
if let resourceDirPath = ProcessInfo.processInfo.environment["SWIFTCI_INSTALL_RPATH_OS"] {
    swiftpmLinkSettings = [.unsafeFlags([
        "-no-toolchain-stdlib-rpath",
        "-Xlinker", "-rpath",
        "-Xlinker", "$ORIGIN/../lib/swift/\(resourceDirPath)",
    ])]
    packageLibraryLinkSettings = [.unsafeFlags([
        "-no-toolchain-stdlib-rpath",
        "-Xlinker", "-rpath",
        "-Xlinker", "$ORIGIN/../../\(resourceDirPath)",
    ])]
} else {
    swiftpmLinkSettings = []
    packageLibraryLinkSettings = []
}

// Common experimental flags to be added to all targets.
let commonExperimentalFeatures: [SwiftSetting] = [
    .enableExperimentalFeature("MemberImportVisibility"),
]

// Certain targets fail to compile with MemberImportVisibility enabled on 6.0.3
// but work with >=6.1. These targets opt in to using `swift6CompatibleExperimentalFeatures`.
#if swift(>=6.1)
let swift6CompatibleExperimentalFeatures = commonExperimentalFeatures
#else
let swift6CompatibleExperimentalFeatures: [SwiftSetting] = []
#endif

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
        "PackageMetadata",
        "PackageModel",
        "PackageModelSyntax",
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
        "SourceKitLSPAPI",
        "SPMLLBuild",
        "SwiftBuildSupport",
    ]
)

#if os(Windows)
let includeDynamicLibrary: Bool = false
let systemSQLitePkgConfig: String? = nil
#else
let includeDynamicLibrary: Bool = true
var systemSQLitePkgConfig: String? = "sqlite3"
if ProcessInfo.processInfo.environment["SWIFTCI_INSTALL_RPATH_OS"] == "android" {
    systemSQLitePkgConfig = nil
}
#endif

/** An array of products which have two versions listed: one dynamically linked, the other with the
 automatic linking type with `-auto` suffix appended to product's name.
 */
let autoProducts = [swiftPMProduct, swiftPMDataModelProduct]

let shoudUseSwiftBuildFramework = (ProcessInfo.processInfo.environment["SWIFTPM_SWBUILD_FRAMEWORK"] != nil)

let swiftDriverDeps: [Target.Dependency]
let swiftTSCBasicsDeps: [Target.Dependency]
let swiftToolsCoreSupportAutoDeps: [Target.Dependency]
let swiftTSCTestSupportDeps: [Target.Dependency]

if shoudUseSwiftBuildFramework {
    swiftDriverDeps = []
    swiftTSCBasicsDeps = []
    swiftToolsCoreSupportAutoDeps = []
    swiftTSCTestSupportDeps = []
} else {
    swiftDriverDeps = [
        .product(name: "SwiftDriver", package: "swift-driver")
    ]
    swiftTSCBasicsDeps = [
        .product(name: "TSCBasic", package: "swift-tools-support-core"),
    ]
    swiftToolsCoreSupportAutoDeps = [
        .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core")
    ]
    swiftTSCTestSupportDeps = [
        .product(name: "TSCTestSupport", package: "swift-tools-support-core"),
    ]
}
let package = Package(
    name: "SwiftPM",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
        .macCatalyst(.v17),
    ],
    products:
    autoProducts.flatMap {
        (includeDynamicLibrary ? [
            .library(
                name: $0.name,
                type: .dynamic,
                targets: $0.targets
            ),
        ] : [])
        +
        [
            .library(
                name: "\($0.name)-auto",
                targets: $0.targets
            ),
        ]
    } + [
        .library(
            name: "XCBuildSupport",
            targets: ["XCBuildSupport"]
        ),
        .library(
            name: "PackageDescription",
            type: .dynamic,
            targets: ["PackageDescription", "CompilerPluginSupport"]
        ),
        .library(
            name: "AppleProductTypes",
            type: .dynamic,
            targets: ["AppleProductTypes"]
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
    targets: [
        // The `PackageDescription` target provides the API that is available
        // to `Package.swift` manifests. Here we build a debug version of the
        // library; the bootstrap scripts build the deployable version.
        .target(
            name: "PackageDescription",
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .define("USE_IMPL_ONLY_IMPORTS"),
                .unsafeFlags(["-package-description-version", "999.0"]),
                .unsafeFlags(["-enable-library-evolution"]),
            ],
            linkerSettings: packageLibraryLinkSettings
        ),

        // The `AppleProductTypes` target provides additional product types
        // to `Package.swift` manifests. Here we build a debug version of the
        // library; the bootstrap scripts build the deployable version.
        .target(
            name: "AppleProductTypes",
            // Note: We use `-module-link-name` so clients link against the
            // AppleProductTypes library when they import it without further
            // messing with the manifest loader.
            dependencies: ["PackageDescription"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-package-description-version", "999.0"]),
                .unsafeFlags(["-enable-library-evolution"], .when(platforms: [.macOS])),
                .unsafeFlags(["-Xfrontend", "-module-link-name", "-Xfrontend", "AppleProductTypes"])
            ]),

        // The `PackagePlugin` target provides the API that is available to
        // plugin scripts. Here we build a debug version of the library; the
        // bootstrap scripts build the deployable version.
        .target(
            name: "PackagePlugin",
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-package-description-version", "999.0"]),
                .unsafeFlags(["-enable-library-evolution"]),
            ],
            linkerSettings: packageLibraryLinkSettings
        ),

        .target(
            name: "SourceKitLSPAPI",
            dependencies: [
                "Basics",
                "Build",
                "PackageGraph",
                "PackageLoading",
                "PackageModel",
                "SPMBuildCore",
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .enableExperimentalFeature("AccessLevelOnImport"),
                .unsafeFlags(["-static"]),
            ]
        ),

        // MARK: SwiftPM specific support libraries

        .systemLibrary(name: "SPMSQLite3", pkgConfig: systemSQLitePkgConfig),

        .target(
            name: "_AsyncFileSystem",
            dependencies: [
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .enableExperimentalFeature("StrictConcurrency"),
                .enableExperimentalFeature("AccessLevelOnImport"),
                .enableExperimentalFeature("InternalImportsByDefault"),
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            name: "Basics",
            dependencies: [
                "_AsyncFileSystem",
                .target(name: "SPMSQLite3", condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .macCatalyst, .linux, .openbsd, .custom("freebsd")])),
                .product(name: "SwiftToolchainCSQLite", package: "swift-toolchain-sqlite", condition: .when(platforms: [.windows, .android])),
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "SystemPackage", package: "swift-system"),
            ] + swiftToolsCoreSupportAutoDeps,
            exclude: ["CMakeLists.txt", "Vendor/README.md"],
            swiftSettings: swift6CompatibleExperimentalFeatures + [
                .enableExperimentalFeature("StrictConcurrency"),
                .enableExperimentalFeature("AccessLevelOnImport"),
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            /** The llbuild manifest model */
            name: "LLBuildManifest",
            dependencies: ["Basics"],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            /** Package registry support */
            name: "PackageRegistry",
            dependencies: [
                "Basics",
                "PackageFingerprint",
                "PackageLoading",
                "PackageModel",
                "PackageSigning",
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            /** Source control operations */
            name: "SourceControl",
            dependencies: [
                "Basics",
                "PackageModel",
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            /** Shim for llbuild library */
            name: "SPMLLBuild",
            dependencies: ["Basics"],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            /** API for deserializing diagnostics and applying fix-its */
            name: "SwiftFixIt",
            dependencies: [
                "Basics",
            ] + swiftTSCBasicsDeps + swiftSyntaxDependencies(
                ["SwiftDiagnostics", "SwiftIDEUtils", "SwiftParser", "SwiftSyntax"]
            ),
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            /** API for inspecting symbols defined in binaries */
            name: "BinarySymbols",
            dependencies: [
                "Basics",
            ] + swiftTSCBasicsDeps,
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        // MARK: Project Model

        .target(
            /** Primitive Package model objects */
            name: "PackageModel",
            dependencies: ["Basics"],
            exclude: ["CMakeLists.txt", "README.md"],
            swiftSettings: swift6CompatibleExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            /** Primary Package model objects relationship to SwiftSyntax */
            name: "PackageModelSyntax",
            dependencies: [
                "Basics",
                "PackageLoading",
                "PackageModel",
            ] + swiftSyntaxDependencies(["SwiftBasicFormat", "SwiftDiagnostics", "SwiftIDEUtils", "SwiftParser", "SwiftSyntax", "SwiftSyntaxBuilder"]),
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            /** Package model conventions and loading support */
            name: "PackageLoading",
            dependencies: [
                "Basics",
                "PackageModel",
                "SourceControl",
            ],
            exclude: ["CMakeLists.txt", "README.md"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        // MARK: Package Dependency Resolution

        .target(
            /** Data structures and support for complete package graphs */
            name: "PackageGraph",
            dependencies: [
                "Basics",
                "PackageLoading",
                "PackageModel",
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            exclude: ["CMakeLists.txt", "README.md"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        // MARK: Package Collections

        .target(
            /** Package collections models */
            name: "PackageCollectionsModel",
            dependencies: [],
            exclude: [
                "Formats/v1.md",
                "CMakeLists.txt",
            ],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
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
            exclude: ["CMakeLists.txt"],
            swiftSettings: swift6CompatibleExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            name: "PackageCollectionsSigning",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                "Basics",
                "PackageCollectionsModel",
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            name: "PackageFingerprint",
            dependencies: [
                "Basics",
                "PackageModel",
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            name: "PackageSigning",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                "Basics",
                "PackageModel",
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        // MARK: Documentation

        .target(
            name: "PackageManagerDocs",
            exclude: ["README.md"],
        ),

        // MARK: Package Manager Functionality

        .target(
            /** Builds Modules and Products */
            name: "SPMBuildCore",
            dependencies: [
                "Basics",
                "PackageGraph",
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
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
                .product(name: "OrderedCollections", package: "swift-collections"),
                "DriverSupport",
            ] + swiftDriverDeps,
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),
        .target(
            name: "DriverSupport",
            dependencies: [
                "Basics",
                "PackageModel",
            ] + swiftDriverDeps,
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),
        .target(
            /** Support for building using Xcode's build system */
            name: "XCBuildSupport",
            dependencies: [
                "SPMBuildCore",
                "PackageGraph",
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),
        .target(
            name: "SwiftBuildSupport",
            dependencies: [
                "SPMBuildCore",
                "PackageGraph",
            ],
            exclude: ["CMakeLists.txt", "README.md"],
            swiftSettings: commonExperimentalFeatures
        ),
        .target(
            /** High level functionality */
            name: "Workspace",
            dependencies: [
                "Basics",
                "PackageFingerprint",
                "PackageGraph",
                "PackageModel",
                "PackageRegistry",
                "PackageSigning",
                "SourceControl",
                "SPMBuildCore",
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),
        .target(
            // ** High level interface for package discovery */
            name: "PackageMetadata",
            dependencies: [
                "Basics",
                "PackageCollections",
                "PackageModel",
                "PackageRegistry",
                "PackageSigning",
            ],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        // MARK: Commands

        .target(
            /** Minimal set of commands required for bootstrapping a new SwiftPM */
            name: "CoreCommands",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Basics",
                "Build",
                "PackageLoading",
                "PackageModel",
                "PackageGraph",
                "Workspace",
                "XCBuildSupport",
                "SwiftBuildSupport",
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            /** High-level commands */
            name: "Commands",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                "Basics",
                "BinarySymbols",
                "Build",
                "CoreCommands",
                "PackageGraph",
                "PackageModelSyntax",
                "SourceControl",
                "Workspace",
                "XCBuildSupport",
                "SwiftBuildSupport",
                "SwiftFixIt",
            ] + swiftSyntaxDependencies(["SwiftIDEUtils"]),
            exclude: ["CMakeLists.txt", "README.md"],
            swiftSettings: swift6CompatibleExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            /** Interacts with Swift SDKs used for cross-compilation */
            name: "SwiftSDKCommand",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Basics",
                "CoreCommands",
                "SPMBuildCore",
                "PackageModel",
            ],
            exclude: ["CMakeLists.txt", "README.md"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            /** Interacts with package collections */
            name: "PackageCollectionsCommand",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Basics",
                "Commands",
                "CoreCommands",
                "PackageCollections",
                "PackageModel",
            ],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            /** Interact with package registry */
            name: "PackageRegistryCommand",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Basics",
                "Commands",
                "CoreCommands",
                "PackageGraph",
                "PackageLoading",
                "PackageModel",
                "PackageRegistry",
                "PackageSigning",
                "SourceControl",
                "SPMBuildCore",
                "Workspace",
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-static"]),
            ]
        ),

        .target(
            name: "QueryEngine",
            dependencies: [
                "_AsyncFileSystem",
                "Basics",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete"),
                .unsafeFlags(["-static"]),
            ]
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
            /** Builds SwiftPM itself for bootstrapping (minimal version of `swift-build`) */
            name: "swift-bootstrap",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                "Basics",
                "Build",
                "PackageGraph",
                "PackageLoading",
                "PackageModel",
                "XCBuildSupport",
                "SwiftBuildSupport",
            ],
            exclude: ["CMakeLists.txt"]
        ),
        .executableTarget(
            /** Interacts with Swift SDKs used for cross-compilation */
            name: "swift-sdk",
            dependencies: ["Commands", "SwiftSDKCommand"],
            exclude: ["CMakeLists.txt"]
        ),
        .executableTarget(
            /** Deprecated command superseded by `swift-sdk` */
            name: "swift-experimental-sdk",
            dependencies: ["Commands", "SwiftSDKCommand"],
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
            dependencies: ["Commands", "PackageCollectionsCommand"]
        ),
        .executableTarget(
            /** Multi-command entry point for SwiftPM. */
            name: "swift-package-manager",
            dependencies: [
                "Basics",
                "Commands",
                "SwiftSDKCommand",
                "PackageCollectionsCommand",
                "PackageRegistryCommand",
            ],
            linkerSettings: swiftpmLinkSettings
        ),
        .executableTarget(
            /** Interact with package registry */
            name: "swift-package-registry",
            dependencies: ["Commands", "PackageRegistryCommand"]
        ),
        .executableTarget(
            /** Utility to produce the artifacts for prebuilts */
            name: "swift-build-prebuilts",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Basics",
                "Workspace",
            ]
        ),

        // MARK: Support for Swift macros, should eventually move to a plugin-based solution

        .target(
            name: "CompilerPluginSupport",
            dependencies: ["PackageDescription"],
            exclude: ["CMakeLists.txt"],
            swiftSettings: commonExperimentalFeatures + [
                .unsafeFlags(["-package-description-version", "999.0"]),
                .unsafeFlags(["-enable-library-evolution"]),
            ]
        ),

        // MARK: Additional Test Dependencies

            .target(
                /** SwiftPM internal build test suite support library */
                name: "_InternalBuildTestSupport",
                dependencies: [
                    "Build",
                    "XCBuildSupport",
                    "SwiftBuildSupport",
                    "_InternalTestSupport"
                ],
                swiftSettings: [
                    .unsafeFlags(["-static"]),
                ]
            ),

        .target(
            /** SwiftPM internal test suite support library */
            name: "_InternalTestSupport",
            dependencies: [
                "Basics",
                "PackageFingerprint",
                "PackageGraph",
                "PackageLoading",
                "PackageRegistry",
                "PackageSigning",
                "SourceControl",
                .product(name: "OrderedCollections", package: "swift-collections"),
                "Workspace",
            ] + swiftTSCTestSupportDeps,
            swiftSettings: [
                .unsafeFlags(["-static"]),
            ]
        ),
        .target(
            /** SwiftPM internal test suite support library */
            name: "_IntegrationTestSupport",
            dependencies: [
                "_InternalTestSupport",
            ] + swiftTSCTestSupportDeps,
        ),

        .target(
            /** Test for thread-sanitizer. */
            name: "tsan_utils",
            dependencies: [],
            swiftSettings: [
                .unsafeFlags(["-static"]),
            ]
        ),

        // MARK: SwiftPM tests

        .testTarget(
            name: "_AsyncFileSystemTests",
            dependencies: [
                "_AsyncFileSystem",
                "_InternalTestSupport",
            ]
        ),

        .testTarget(
            name: "SourceKitLSPAPITests",
            dependencies: [
                "SourceKitLSPAPI",
                "_InternalTestSupport",
            ]
        ),

        .testTarget(
            name: "BasicsTests",
            dependencies: [
                "Basics",
                "_InternalTestSupport",
                "tsan_utils",
            ],
            exclude: [
                "Archiver/Inputs/archive.tar.gz",
                "Archiver/Inputs/archive.zip",
                "Archiver/Inputs/invalid_archive.tar.gz",
                "Archiver/Inputs/invalid_archive.zip",
                "processInputs/long-stdout-stderr",
                "processInputs/long-stdout-stderr.bat",
                "processInputs/exit4",
                "processInputs/exit4.bat",
                "processInputs/simple-stdout-stderr",
                "processInputs/simple-stdout-stderr.bat",
                "processInputs/deadlock-if-blocking-io",
                "processInputs/deadlock-if-blocking-io.bat",
                "processInputs/echo",
                "processInputs/echo.bat",
                "processInputs/in-to-out",
                "processInputs/in-to-out.bat",
            ]
        ),
        .testTarget(
            name: "BuildTests",
            dependencies: ["Build", "PackageModel", "Commands", "_InternalTestSupport", "_InternalBuildTestSupport"]
        ),
        .testTarget(
            name: "LLBuildManifestTests",
            dependencies: ["Basics", "LLBuildManifest", "_InternalTestSupport"]
        ),
        .testTarget(
            name: "WorkspaceTests",
            dependencies: ["Workspace", "_InternalTestSupport"]
        ),
        .testTarget(
            name: "PackageDescriptionTests",
            dependencies: ["PackageDescription"]
        ),
        .testTarget(
            name: "SPMBuildCoreTests",
            dependencies: ["SPMBuildCore", "_InternalTestSupport"]
        ),
        .testTarget(
            name: "PackageLoadingTests",
            dependencies: ["PackageLoading", "_InternalTestSupport"],
            exclude: ["Inputs", "pkgconfigInputs"]
        ),
        .testTarget(
            name: "PackageModelTests",
            dependencies: ["PackageModel", "_InternalTestSupport"]
        ),
        .testTarget(
            name: "PackageModelSyntaxTests",
            dependencies: [
                "PackageModelSyntax",
                "_InternalTestSupport",
            ] + swiftSyntaxDependencies(["SwiftIDEUtils"])
        ),
        .testTarget(
            name: "PackageGraphTests",
            dependencies: ["PackageGraph", "_InternalTestSupport"],
            swiftSettings: commonExperimentalFeatures
        ),
        .testTarget(
            name: "PackageGraphPerformanceTests",
            dependencies: ["PackageGraph", "_InternalTestSupport"],
            exclude: [
                "Inputs/PerfectHTTPServer.json",
                "Inputs/ZewoHTTPServer.json",
                "Inputs/SourceKitten.json",
                "Inputs/kitura.json",
            ]
        ),
        .testTarget(
            name: "PackageCollectionsModelTests",
            dependencies: ["PackageCollectionsModel", "_InternalTestSupport"]
        ),
        .testTarget(
            name: "PackageCollectionsSigningTests",
            dependencies: ["PackageCollectionsSigning", "_InternalTestSupport"]
        ),
        .testTarget(
            name: "PackageCollectionsTests",
            dependencies: ["PackageCollections", "_InternalTestSupport", "tsan_utils"]
        ),
        .testTarget(
            name: "PackageFingerprintTests",
            dependencies: ["PackageFingerprint", "_InternalTestSupport"]
        ),
        .testTarget(
            name: "PackagePluginAPITests",
            dependencies: ["PackagePlugin", "_InternalTestSupport"]
        ),
        .testTarget(
            name: "PackageRegistryTests",
            dependencies: ["_InternalTestSupport", "PackageRegistry"]
        ),
        .testTarget(
            name: "PackageSigningTests",
            dependencies: ["_InternalTestSupport", "PackageSigning"]
        ),
        .testTarget(
            name: "QueryEngineTests",
            dependencies: ["QueryEngine", "_InternalTestSupport"]
        ),
        .testTarget(
            name: "SourceControlTests",
            dependencies: ["SourceControl", "_InternalTestSupport"],
            exclude: ["Inputs/TestRepo.tgz"]
        ),
        .testTarget(
            name: "SwiftFixItTests",
            dependencies: ["SwiftFixIt", "_InternalTestSupport"]
        ),
        .testTarget(
            name: "BinarySymbolsTests",
            dependencies: ["BinarySymbols", "_InternalTestSupport"]
        ),
        .testTarget(
            name: "XCBuildSupportTests",
            dependencies: ["XCBuildSupport", "_InternalTestSupport", "_InternalBuildTestSupport"],
            exclude: ["Inputs/Foo.pc"]
        ),
        .testTarget(
            name: "FunctionalPerformanceTests",
            dependencies: [
                "swift-package-manager",
                "_InternalTestSupport",
            ]
        ),
        // Examples (These are built to ensure they stay up to date with the API.)
        .executableTarget(
            name: "package-info",
            dependencies: ["Workspace"],
            path: "Examples/package-info/Sources/package-info"
        )
    ],
    swiftLanguageModes: [.v5]
)

#if canImport(Darwin)
package.targets.append(contentsOf: [
    .executableTarget(
        name: "swiftpm-testing-helper"
    )
])
#endif

// rdar://101868275 "error: cannot find 'XCTAssertEqual' in scope" can affect almost any functional test, so we flat out
// disable them all until we know what is going on
if ProcessInfo.processInfo.environment["SWIFTCI_DISABLE_SDK_DEPENDENT_TESTS"] == nil {
    package.targets.append(contentsOf: [
        .testTarget(
            name: "FunctionalTests",
            dependencies: [
                "swift-package-manager",
                "PackageModel",
                "_InternalTestSupport",
            ]
        ),
        .executableTarget(
            name: "dummy-swiftc",
            dependencies: [
                "Basics",
            ]
        ),
        .testTarget(
            name: "_InternalTestSupportTests",
            dependencies: [
                "_InternalTestSupport"
            ]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: [
                "_IntegrationTestSupport",
                "_InternalTestSupport",
            ] + swiftTSCTestSupportDeps + swiftToolsCoreSupportAutoDeps,
        ),
        .testTarget(
            name: "CommandsTests",
            dependencies: [
                "swift-package-manager",
                "Basics",
                "Build",
                "Commands",
                "PackageModel",
                "PackageModelSyntax",
                "PackageRegistryCommand",
                "SourceControl",
                "_InternalTestSupport",
                "Workspace",
                "dummy-swiftc",
            ]
        ),
    ])
}


func swiftSyntaxDependencies(_ names: [String]) -> [Target.Dependency] {
  /// Whether swift-syntax is being built as a single dynamic library instead of as a separate library per module.
  ///
  /// This means that the swift-syntax symbols don't need to be statically linked, which allows us to stay below the
  /// maximum number of exported symbols on Windows, in turn allowing us to build sourcekit-lsp using SwiftPM on Windows
  /// and run its tests.
  let buildDynamicSwiftSyntaxLibrary = ProcessInfo.processInfo.environment["SWIFTSYNTAX_BUILD_DYNAMIC_LIBRARY"] != nil
  if buildDynamicSwiftSyntaxLibrary {
    return [.product(name: "_SwiftSyntaxDynamic", package: "swift-syntax")]
  } else {
    return names.map { .product(name: $0, package: "swift-syntax") }
  }
}

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
            .package(url: "https://github.com/swiftlang/swift-llbuild.git", branch: relatedDependenciesBranch),
        ]
    } else {
        // In Swift CI, use a local path to llbuild to interoperate with tools
        // like `update-checkout`, which control the sources externally.
        package.dependencies += [
            .package(name: "swift-llbuild", path: "../llbuild"),
        ]
    }
    package.targets.first(where: { $0.name == "SPMLLBuild" })!.dependencies += [
        .product(name: "llbuildSwift", package: "swift-llbuild"),
    ]
}

if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
    package.dependencies += [
        // The 'swift-argument-parser' version declared here must match that
        // used by 'swift-driver' and 'sourcekit-lsp'. Please coordinate
        // dependency version changes here with those projects.
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.5.1")),
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMinor(from: "3.0.0")),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", branch: relatedDependenciesBranch),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.1.1"),
        .package(url: "https://github.com/apple/swift-collections.git", "1.0.1" ..< "1.2.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", "1.0.1" ..< "1.6.0"),
        .package(url: "https://github.com/swiftlang/swift-toolchain-sqlite.git", from: "1.0.0"),
        // For use in previewing documentation
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.1.0"),
    ]
    if !swiftDriverDeps.isEmpty {
        package.dependencies += [
            .package(url: "https://github.com/swiftlang/swift-tools-support-core.git", branch: relatedDependenciesBranch),
            .package(url: "https://github.com/swiftlang/swift-driver.git", branch: relatedDependenciesBranch),
        ]
    }
} else {
    package.dependencies += [
        .package(path: "../swift-argument-parser"),
        .package(path: "../swift-crypto"),
        .package(path: "../swift-syntax"),
        .package(path: "../swift-system"),
        .package(path: "../swift-collections"),
        .package(path: "../swift-certificates"),
        .package(path: "../swift-toolchain-sqlite"),
    ]
    if !swiftDriverDeps.isEmpty {
        package.dependencies += [
            .package(path: "../swift-tools-support-core"),
            .package(path: "../swift-driver"),
        ]
    }

}

/// If ENABLE_APPLE_PRODUCT_TYPES is set in the environment, then also define ENABLE_APPLE_PRODUCT_TYPES in each of the regular targets and test targets.
if ProcessInfo.processInfo.environment["ENABLE_APPLE_PRODUCT_TYPES"] == "1" {
    for target in package.targets.filter({ $0.type == .regular || $0.type == .test }) {
        target.swiftSettings = (target.swiftSettings ?? []) + [ .define("ENABLE_APPLE_PRODUCT_TYPES") ]
    }
}

if !shoudUseSwiftBuildFramework {

    let swiftbuildsupport: Target = package.targets.first(where: { $0.name == "SwiftBuildSupport" } )!
    swiftbuildsupport.dependencies += [
        .product(name: "SwiftBuild", package: "swift-build"),
    ]

    swiftbuildsupport.dependencies += [
        // This is here to statically link the build service in the same executable as SwiftPM
        .product(name: "SWBBuildService", package: "swift-build"),
    ]

    if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
        package.dependencies += [
            .package(url: "https://github.com/swiftlang/swift-build.git", branch: relatedDependenciesBranch),
        ]
    } else {
        package.dependencies += [
            .package(path: "../swift-build"),
        ]
    }
}
