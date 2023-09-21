// swift-tools-version:5.8

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageDescription
import class Foundation.ProcessInfo

// When building the toolchain on the CI for ELF platforms, remove the CI's
// stdlib absolute runpath and add ELF's $ORIGIN relative paths before installing.
let swiftpmLinkSettings : [LinkerSetting]
let packageLibraryLinkSettings : [LinkerSetting]
if let resourceDirPath = ProcessInfo.processInfo.environment["SWIFTCI_INSTALL_RPATH_OS"] {
  swiftpmLinkSettings = [ .unsafeFlags(["-no-toolchain-stdlib-rpath", "-Xlinker", "-rpath", "-Xlinker", "$ORIGIN/../lib/swift/\(resourceDirPath)"]) ]
  packageLibraryLinkSettings = [ .unsafeFlags(["-no-toolchain-stdlib-rpath", "-Xlinker", "-rpath", "-Xlinker", "$ORIGIN/../../\(resourceDirPath)"]) ]
} else {
  swiftpmLinkSettings = []
  packageLibraryLinkSettings = []
}

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

#if os(Windows)
let systemSQLitePkgConfig: String? = nil
#else
let systemSQLitePkgConfig: String? = "sqlite3"
#endif

#if swift(>=5.10)
let enabledFeatures: [SwiftSetting] = [
    .enableExperimentalFeature("AccessLevelOnImport")
]
#else
let enabledFeatures: [SwiftSetting] = []
#endif

/** An array of products which have two versions listed: one dynamically linked, the other with the
automatic linking type with `-auto` suffix appended to product's name.
*/
let autoProducts = [swiftPMProduct, swiftPMDataModelProduct]

let package = Package(
    name: "SwiftPM",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
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
            targets: ["PackageDescription", "CompilerPluginSupport"]
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
            swiftSettings: [
                .unsafeFlags(["-package-description-version", "999.0"]),
                .unsafeFlags(["-enable-library-evolution"]),
            ] + enabledFeatures,
            linkerSettings: packageLibraryLinkSettings
        ),

        // The `PackagePlugin` target provides the API that is available to
        // plugin scripts. Here we build a debug version of the library; the
        // bootstrap scripts build the deployable version.
        .target(
            name: "PackagePlugin",
            exclude: ["CMakeLists.txt"],
            swiftSettings: [
                .unsafeFlags(["-package-description-version", "999.0"]),
                .unsafeFlags(["-enable-library-evolution"]),
            ] + enabledFeatures,
            linkerSettings: packageLibraryLinkSettings
        ),

        // MARK: SwiftPM specific support libraries

        .systemLibrary(name: "SPMSQLite3", pkgConfig: systemSQLitePkgConfig),

        .target(
            name: "Basics",
            dependencies: [
                "SPMSQLite3",
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "SwiftToolsSupport-auto", package: "swift-tools-support-core"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            exclude: ["CMakeLists.txt", "Vendor/README.md"],
            swiftSettings: enabledFeatures
        ),

        .target(
            /** The llbuild manifest model */
            name: "LLBuildManifest",
            dependencies: ["Basics"],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
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
            swiftSettings: enabledFeatures
        ),

        .target(
            /** Source control operations */
            name: "SourceControl",
            dependencies: [
                "Basics",
                "PackageModel"
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
        ),

        .target(
            /** Shim for llbuild library */
            name: "SPMLLBuild",
            dependencies: ["Basics"],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
        ),

        // MARK: Project Model

        .target(
            /** Primitive Package model objects */
            name: "PackageModel",
            dependencies: ["Basics"],
            exclude: ["CMakeLists.txt", "README.md"],
            swiftSettings: enabledFeatures
        ),

        .target(
            /** Package model conventions and loading support */
            name: "PackageLoading",
            dependencies: [
                "Basics",
                "PackageModel"
            ],
            exclude: ["CMakeLists.txt", "README.md"],
            swiftSettings: enabledFeatures
        ),

        // MARK: Package Dependency Resolution

        .target(
            /** Data structures and support for complete package graphs */
            name: "PackageGraph",
            dependencies: [
                "Basics",
                "PackageLoading",
                "PackageModel"
            ],
            exclude: ["CMakeLists.txt", "README.md"],
            swiftSettings: enabledFeatures
        ),

        // MARK: Package Collections

        .target(
            /** Package collections models */
            name: "PackageCollectionsModel",
            dependencies: [],
            exclude: [
                "Formats/v1.md"
            ],
            swiftSettings: enabledFeatures
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
            swiftSettings: enabledFeatures
        ),

        .target(
            name: "PackageCollectionsSigning",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                "Basics",
                "PackageCollectionsModel",
            ],
            swiftSettings: enabledFeatures
        ),

        .target(
            name: "PackageFingerprint",
            dependencies: [
                "Basics",
                "PackageModel",
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
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
            swiftSettings: enabledFeatures
        ),

        // MARK: Package Manager Functionality

        .target(
            /** Builds Modules and Products */
            name: "SPMBuildCore",
            dependencies: [
                "Basics",
                "PackageGraph"
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
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
                "DriverSupport",
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
        ),
        .target(
            name: "DriverSupport",
            dependencies: [
                "Basics",
                "PackageModel",
                .product(name: "SwiftDriver", package: "swift-driver"),
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
        ),
        .target(
            /** Support for building using Xcode's build system */
            name: "XCBuildSupport",
            dependencies: ["SPMBuildCore", "PackageGraph"],
            exclude: ["CMakeLists.txt", "CODEOWNERS"],
            swiftSettings: enabledFeatures
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
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
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
            swiftSettings: enabledFeatures
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
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
        ),

        .target(
            /** High-level commands */
            name: "Commands",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Basics",
                "Build",
                "CoreCommands",
                "PackageGraph",
                "SourceControl",
                "Workspace",
                "XCBuildSupport",
            ],
            exclude: ["CMakeLists.txt", "README.md"],
            swiftSettings: enabledFeatures
        ),

        .target(
            /** Interacts with Swift SDKs used for cross-compilation */
            name: "SwiftSDKTool",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Basics",
                "CoreCommands",
                "SPMBuildCore",
                "PackageModel",
            ],
            exclude: ["CMakeLists.txt", "README.md"],
            swiftSettings: enabledFeatures
        ),

        .target(
            /** Interacts with package collections */
            name: "PackageCollectionsTool",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Basics",
                "Commands",
                "CoreCommands",
                "PackageCollections",
                "PackageModel",
            ],
            swiftSettings: enabledFeatures
        ),

        .target(
            /** Interact with package registry */
            name: "PackageRegistryTool",
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
            swiftSettings: enabledFeatures
        ),

        .executableTarget(
            /** The main executable provided by SwiftPM */
            name: "swift-package",
            dependencies: ["Basics", "Commands"],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
        ),
        .executableTarget(
            /** Builds packages */
            name: "swift-build",
            dependencies: ["Commands"],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
        ),
        .executableTarget(
            /** Builds SwiftPM itself for bootstrapping (minimal version of `swift-build`) */
            name: "swift-bootstrap",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Basics",
                "Build",
                "PackageGraph",
                "PackageLoading",
                "PackageModel",
                "XCBuildSupport",
            ],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
        ),
        .executableTarget(
            /** Interacts with Swift SDKs used for cross-compilation */
            name: "swift-experimental-sdk",
            dependencies: ["Commands", "SwiftSDKTool"],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
        ),
        .executableTarget(
            /** Runs package tests */
            name: "swift-test",
            dependencies: ["Commands"],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
        ),
        .executableTarget(
            /** Runs an executable product */
            name: "swift-run",
            dependencies: ["Commands"],
            exclude: ["CMakeLists.txt"],
            swiftSettings: enabledFeatures
        ),
        .executableTarget(
            /** Interacts with package collections */
            name: "swift-package-collection",
            dependencies: ["Commands", "PackageCollectionsTool"],
            swiftSettings: enabledFeatures
        ),
        .executableTarget(
            /** Multi-tool entry point for SwiftPM. */
            name: "swift-package-manager",
            dependencies: [
                "Basics",
                "Commands",
                "SwiftSDKTool",
                "PackageCollectionsTool",
                "PackageRegistryTool"
            ],
            swiftSettings: enabledFeatures,
            linkerSettings: swiftpmLinkSettings
        ),
        .executableTarget(
            /** Interact with package registry */
            name: "swift-package-registry",
            dependencies: ["Commands", "PackageRegistryTool"],
            swiftSettings: enabledFeatures
        ),

        // MARK: Support for Swift macros, should eventually move to a plugin-based solution

        .target(
            name: "CompilerPluginSupport",
            dependencies: ["PackageDescription"],
            exclude: ["CMakeLists.txt"],
            swiftSettings: [
                .unsafeFlags(["-package-description-version", "999.0"]),
                .unsafeFlags(["-enable-library-evolution"]),
            ] + enabledFeatures
        ),

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
                "PackageSigning",
                "SourceControl",
                .product(name: "TSCTestSupport", package: "swift-tools-support-core"),
                "Workspace",
                "XCBuildSupport",
            ],
            swiftSettings: enabledFeatures
        ),

        .target(
            /** Test for thread-santizer. */
            name: "tsan_utils",
            dependencies: [],
            swiftSettings: enabledFeatures
        ),

        // MARK: SwiftPM tests

        .testTarget(
            name: "BasicsTests",
            dependencies: ["Basics", "SPMTestSupport", "tsan_utils"],
            exclude: [
                "Archiver/Inputs/archive.tar.gz",
                "Archiver/Inputs/archive.zip",
                "Archiver/Inputs/invalid_archive.tar.gz",
                "Archiver/Inputs/invalid_archive.zip",
            ],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "BuildTests",
            dependencies: ["Build", "PackageModel", "SPMTestSupport"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "LLBuildManifestTests",
            dependencies: ["Basics", "LLBuildManifest", "SPMTestSupport"]
        ),
        .testTarget(
            name: "WorkspaceTests",
            dependencies: ["Workspace", "SPMTestSupport"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "PackageDescriptionTests",
            dependencies: ["PackageDescription"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "SPMBuildCoreTests",
            dependencies: ["SPMBuildCore", "SPMTestSupport"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "PackageLoadingTests",
            dependencies: ["PackageLoading", "SPMTestSupport"],
            exclude: ["Inputs", "pkgconfigInputs"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "PackageLoadingPerformanceTests",
            dependencies: ["PackageLoading", "SPMTestSupport"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "PackageModelTests",
            dependencies: ["PackageModel", "SPMTestSupport"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "PackageGraphTests",
            dependencies: ["PackageGraph", "SPMTestSupport"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "PackageGraphPerformanceTests",
            dependencies: ["PackageGraph", "SPMTestSupport"],
            exclude: [
                "Inputs/PerfectHTTPServer.json",
                "Inputs/ZewoHTTPServer.json",
                "Inputs/SourceKitten.json",
                "Inputs/kitura.json",
            ],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "PackageCollectionsModelTests",
            dependencies: ["PackageCollectionsModel", "SPMTestSupport"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "PackageCollectionsSigningTests",
            dependencies: ["PackageCollectionsSigning", "SPMTestSupport"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "PackageCollectionsTests",
            dependencies: ["PackageCollections", "SPMTestSupport", "tsan_utils"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "PackageFingerprintTests",
            dependencies: ["PackageFingerprint", "SPMTestSupport"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "PackagePluginAPITests",
            dependencies: ["PackagePlugin", "SPMTestSupport"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "PackageRegistryTests",
            dependencies: ["SPMTestSupport", "PackageRegistry"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "PackageSigningTests",
            dependencies: ["SPMTestSupport", "PackageSigning"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "SourceControlTests",
            dependencies: ["SourceControl", "SPMTestSupport"],
            exclude: ["Inputs/TestRepo.tgz"],
            swiftSettings: enabledFeatures
        ),
        .testTarget(
            name: "XCBuildSupportTests",
            dependencies: ["XCBuildSupport", "SPMTestSupport"],
            exclude: ["Inputs/Foo.pc"],
            swiftSettings: enabledFeatures
        ),
        // Examples (These are built to ensure they stay up to date with the API.)
        .executableTarget(
            name: "package-info",
            dependencies: ["Workspace"],
            path: "Examples/package-info/Sources/package-info",
            swiftSettings: enabledFeatures
        )
    ],
    swiftLanguageVersions: [.v5]
)

// Workaround SPM's attempt to link in executables which does not work on all
// platforms.
#if !os(Windows)
package.targets.append(contentsOf: [
    .testTarget(
        name: "FunctionalPerformanceTests",
        dependencies: [
            "swift-build",
            "swift-package",
            "swift-test",
            "SPMTestSupport"
        ],
        swiftSettings: enabledFeatures
    ),
])

// rdar://101868275 "error: cannot find 'XCTAssertEqual' in scope" can affect almost any functional test, so we flat out disable them all until we know what is going on
if ProcessInfo.processInfo.environment["SWIFTCI_DISABLE_SDK_DEPENDENT_TESTS"] == nil {
    package.targets.append(contentsOf: [
        .testTarget(
            name: "FunctionalTests",
            dependencies: [
                "swift-build",
                "swift-package",
                "swift-test",
                "PackageModel",
                "SPMTestSupport"
            ],
            swiftSettings: enabledFeatures
        ),

        .executableTarget(
            name: "dummy-swiftc",
            dependencies: [
                "Basics",
            ],
            swiftSettings: enabledFeatures
        ),

        .testTarget(
            name: "CommandsTests",
            dependencies: [
                "swift-build",
                "swift-package",
                "swift-test",
                "swift-run",
                "Basics",
                "Build",
                "Commands",
                "PackageModel",
                "PackageRegistryTool",
                "SourceControl",
                "SPMTestSupport",
                "Workspace",
                "dummy-swiftc",
            ],
            swiftSettings: enabledFeatures
        ),
    ])
}
#endif

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
            .package(url: "https://github.com/apple/swift-llbuild.git", branch: relatedDependenciesBranch),
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
        .package(url: "https://github.com/apple/swift-tools-support-core.git", branch: relatedDependenciesBranch),
        // The 'swift-argument-parser' version declared here must match that
        // used by 'swift-driver' and 'sourcekit-lsp'. Please coordinate
        // dependency version changes here with those projects.
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.2.2")),
        .package(url: "https://github.com/apple/swift-driver.git", branch: relatedDependenciesBranch),
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMinor(from: "3.0.0")),
        .package(url: "https://github.com/apple/swift-system.git", .upToNextMinor(from: "1.1.1")),
        .package(url: "https://github.com/apple/swift-collections.git", .upToNextMinor(from: "1.0.1")),
        .package(url: "https://github.com/apple/swift-certificates.git", .upToNextMinor(from: "1.0.1")),
    ]
} else {
    package.dependencies += [
        .package(path: "../swift-tools-support-core"),
        .package(path: "../swift-argument-parser"),
        .package(path: "../swift-driver"),
        .package(path: "../swift-crypto"),
        .package(path: "../swift-system"),
        .package(path: "../swift-collections"),
        .package(path: "../swift-certificates"),
    ]
}
