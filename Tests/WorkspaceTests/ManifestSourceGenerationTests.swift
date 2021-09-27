/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import PackageGraph
import PackageLoading
import PackageModel
import SPMTestSupport
import TSCBasic
import Workspace
import XCTest

class ManifestSourceGenerationTests: XCTestCase {

    /// Private function that writes the contents of a package manifest to a temporary package directory and then loads it, then serializes the loaded manifest back out again and loads it once again, after which it compares that no information was lost. Return the source of the newly generated manifest.
    @discardableResult
    private func testManifestWritingRoundTrip(
        manifestContents: String,
        toolsVersion: ToolsVersion,
        toolsVersionHeaderComment: String? = .none,
        additionalImportModuleNames: [String] = [],
        fs: FileSystem = localFileSystem
    ) throws -> String {
        try withTemporaryDirectory { packageDir in
            let observability = ObservabilitySystem.makeForTesting()

            // Write the original manifest file contents, and load it.
            try fs.writeFileContents(packageDir.appending(component: Manifest.filename), bytes: ByteString(encodingAsUTF8: manifestContents))
            let manifestLoader = ManifestLoader(toolchain: ToolchainConfiguration.default)
            let identityResolver = DefaultIdentityResolver()
            let manifest = try tsc_await {
                manifestLoader.load(at: packageDir,
                                    packageIdentity: .plain("Root"),
                                    packageKind: .root(packageDir),
                                    packageLocation: packageDir.pathString,
                                    version: nil,
                                    revision: nil,
                                    toolsVersion: toolsVersion,
                                    identityResolver: identityResolver,
                                    fileSystem: fs,
                                    observabilityScope: observability.topScope,
                                    on: .global(),
                                    completion: $0)
            }

            XCTAssertNoDiagnostics(observability.diagnostics)

            // Generate source code for the loaded manifest,
            let newContents = try manifest.generateManifestFileContents(
                toolsVersionHeaderComment: toolsVersionHeaderComment,
                additionalImportModuleNames: additionalImportModuleNames)

            // Check that the tools version was serialized properly.
            let versionSpacing = (toolsVersion >= .v5_4) ? " " : ""
            XCTAssertMatch(newContents, .prefix("// swift-tools-version:\(versionSpacing)\(toolsVersion.major).\(toolsVersion.minor)"))

            // Write out the generated manifest to replace the old manifest file contents, and load it again.
            try fs.writeFileContents(packageDir.appending(component: Manifest.filename), bytes: ByteString(encodingAsUTF8: newContents))
            let newManifest = try tsc_await {
                manifestLoader.load(at: packageDir,
                                    packageIdentity: .plain("Root"),
                                    packageKind: .root(packageDir),
                                    packageLocation: packageDir.pathString,
                                    version: nil,
                                    revision: nil,
                                    toolsVersion: toolsVersion,
                                    identityResolver: identityResolver,
                                    fileSystem: fs,
                                    observabilityScope: observability.topScope,
                                    on: .global(),
                                    completion: $0)
            }

            XCTAssertNoDiagnostics(observability.diagnostics)

            // Check that all the relevant properties survived.
            let failureDetails = "\n--- ORIGINAL MANIFEST CONTENTS ---\n" + manifestContents + "\n--- REWRITTEN MANIFEST CONTENTS ---\n" + newContents
            XCTAssertEqual(newManifest.toolsVersion, manifest.toolsVersion, failureDetails)
            XCTAssertEqual(newManifest.displayName, manifest.displayName, failureDetails)
            XCTAssertEqual(newManifest.defaultLocalization, manifest.defaultLocalization, failureDetails)
            XCTAssertEqual(newManifest.platforms, manifest.platforms, failureDetails)
            XCTAssertEqual(newManifest.pkgConfig, manifest.pkgConfig, failureDetails)
            XCTAssertEqual(newManifest.providers, manifest.providers, failureDetails)
            XCTAssertEqual(newManifest.products, manifest.products, failureDetails)
            XCTAssertEqual(newManifest.dependencies, manifest.dependencies, failureDetails)
            XCTAssertEqual(newManifest.targets, manifest.targets, failureDetails)
            XCTAssertEqual(newManifest.swiftLanguageVersions, manifest.swiftLanguageVersions, failureDetails)
            XCTAssertEqual(newManifest.cLanguageStandard, manifest.cLanguageStandard, failureDetails)
            XCTAssertEqual(newManifest.cxxLanguageStandard, manifest.cxxLanguageStandard, failureDetails)

            // Return the generated manifest so that the caller can do further testing on it.
            return newContents
        }
    }

    func testBasics() throws {
        let manifestContents = """
            // swift-tools-version:5.3
            // The swift-tools-version declares the minimum version of Swift required to build this package.

            import PackageDescription

            let package = Package(
                name: "MyPackage",
                platforms: [
                    .macOS(.v10_14),
                    .iOS(.v13)
                ],
                products: [
                    // Products define the executables and libraries a package produces, and make them visible to other packages.
                    .library(
                        name: "MyPackage",
                        targets: ["MyPackage"]),
                ],
                dependencies: [
                    // Dependencies declare other packages that this package depends on.
                    // .package(url: /* package url */, from: "1.0.0"),
                ],
                targets: [
                    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
                    // Targets can depend on other targets in this package, and on products in packages this package depends on.
                    .target(
                        name: "MyPackage",
                        dependencies: []),
                    .testTarget(
                        name: "MyPackageTests",
                        dependencies: ["MyPackage"]),
                ]
            )
            """
        try testManifestWritingRoundTrip(manifestContents: manifestContents, toolsVersion: .v5_3)
    }

    func testCustomPlatform() throws {
        let manifestContents = """
            // swift-tools-version:5.6
            // The swift-tools-version declares the minimum version of Swift required to build this package.

            import PackageDescription

            let package = Package(
                name: "MyPackage",
                platforms: [
                    .custom("customOS", versionString: "1.0")
                ],
                products: [
                    // Products define the executables and libraries a package produces, and make them visible to other packages.
                    .library(
                        name: "MyPackage",
                        targets: ["MyPackage"]),
                ],
                dependencies: [
                    // Dependencies declare other packages that this package depends on.
                    // .package(url: /* package url */, from: "1.0.0"),
                ],
                targets: [
                    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
                    // Targets can depend on other targets in this package, and on products in packages this package depends on.
                    .target(
                        name: "MyPackage",
                        dependencies: []),
                    .testTarget(
                        name: "MyPackageTests",
                        dependencies: ["MyPackage"]),
                ]
            )
            """
        try testManifestWritingRoundTrip(manifestContents: manifestContents, toolsVersion: .v5_6)
    }

    func testAdvancedFeatures() throws {
        let manifestContents = """
            // swift-tools-version:5.3
            // The swift-tools-version declares the minimum version of Swift required to build this package.

            import PackageDescription

            let package = Package(
                name: "MyPackage",
                products: [
                    // Products define the executables and libraries a package produces, and make them visible to other packages.
                    .library(
                        name: "MyPackage",
                        targets: ["MyPackage"]),
                ],
                dependencies: [
                    // Dependencies declare other packages that this package depends on.
                    .package(path: "/a/b/c"),
                    .package(name: "abc", path: "/a/b/d"),
                ],
                targets: [
                    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
                    // Targets can depend on other targets in this package, and on products in packages this package depends on.
                    .systemLibrary(
                        name: "SystemLibraryTarget",
                        pkgConfig: "libSystemModule",
                        providers: [
                            .brew(["SystemModule"]),
                        ]),
                    .target(
                        name: "MyPackage",
                        dependencies: [
                            .target(name: "SystemLibraryTarget", condition: .when(platforms: [.macOS]))
                        ],
                        linkerSettings: [
                            .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../../lib/swift/macosx"], .when(platforms: [.iOS])),
                        ]),
                    .testTarget(
                        name: "MyPackageTests",
                        dependencies: ["MyPackage"]),
                ],
                swiftLanguageVersions: [.v5],
                cLanguageStandard: .c11,
                cxxLanguageStandard: .cxx11
            )
            """
        try testManifestWritingRoundTrip(manifestContents: manifestContents, toolsVersion: .v5_3)
    }

    func testPackageDependencyVariations() throws {
        let manifestContents = """
            // swift-tools-version:5.4
            import PackageDescription

            let package = Package(
                name: "MyPackage",
                dependencies: [
                   .package(url: "/foo1", from: "1.0.0"),
                   .package(url: "/foo2", .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")),
                   .package(path: "../foo3"),
                   .package(path: "/path/to/foo4"),
                   .package(url: "/foo5", .exact("1.2.3")),
                   .package(url: "/foo6", "1.2.3"..<"2.0.0"),
                   .package(url: "/foo7", .branch("master")),
                   .package(url: "/foo8", .upToNextMinor(from: "1.3.4")),
                   .package(url: "/foo9", .upToNextMajor(from: "1.3.4")),
                   .package(path: "~/path/to/foo10"),
                   .package(path: "~foo11"),
                   .package(path: "~/path/to/~/foo12"),
                   .package(path: "~"),
                   .package(path: "file:///path/to/foo13"),
                ]
            )
            """
        try testManifestWritingRoundTrip(manifestContents: manifestContents, toolsVersion: .v5_3)
    }

    func testResources() throws {
        let manifestContents = """
            // swift-tools-version:5.3
            import PackageDescription

            let package = Package(
                name: "Resources",
                defaultLocalization: "is",
                targets: [
                    .target(
                        name: "SwiftyResource",
                        resources: [
                            .copy("foo.txt"),
                            .process("a/b/c/"),
                        ]
                    ),
                    .target(
                        name: "SeaResource",
                        resources: [
                            .process("foo.txt", localization: .base),
                        ]
                    ),
                    .target(
                        name: "SieResource",
                        resources: [
                            .copy("bar.boo"),
                        ]
                    ),
                ]
            )
            """
        try testManifestWritingRoundTrip(manifestContents: manifestContents, toolsVersion: .v5_3)
    }

    func testBuildSettings() throws {
        let manifestContents = """
            // swift-tools-version:5.3
            import PackageDescription

            let package = Package(
                name: "Localized",
                targets: [
                    .target(name: "exe",
                        cxxSettings: [
                            .headerSearchPath("ProjectName"),
                            .headerSearchPath("../../.."),
                            .define("ABC=DEF"),
                            .define("GHI", to: "JKL")
                        ]
                    ),
                    .target(
                        name: "MyTool",
                        dependencies: ["Utility"],
                        cSettings: [
                            .headerSearchPath("path/relative/to/my/target"),
                            .define("DISABLE_SOMETHING", .when(platforms: [.iOS], configuration: .release)),
                        ],
                        swiftSettings: [
                            .define("ENABLE_SOMETHING", .when(configuration: .release)),
                        ],
                        linkerSettings: [
                            .linkedLibrary("openssl", .when(platforms: [.linux])),
                        ]
                    ),
                ]
            )
            """
        try testManifestWritingRoundTrip(manifestContents: manifestContents, toolsVersion: .v5_3)
    }

    func testPluginTargets() throws {
        let manifestContents = """
            // swift-tools-version:5.5
            import PackageDescription

            let package = Package(
                name: "Plugins",
                targets: [
                    .plugin(
                        name: "MyPlugin",
                        capability: .buildTool(),
                        dependencies: ["MyTool"]
                    ),
                    .executableTarget(
                        name: "MyTool"
                    ),
                ]
            )
            """
        try testManifestWritingRoundTrip(manifestContents: manifestContents, toolsVersion: .v5_5)
    }

    func testCustomToolsVersionHeaderComment() throws {
        let manifestContents = """
            // swift-tools-version:5.5
            import PackageDescription

            let package = Package(
                name: "Plugins",
                targets: [
                    .plugin(
                        name: "MyPlugin",
                        capability: .buildTool(),
                        dependencies: ["MyTool"]
                    ),
                    .executableTarget(
                        name: "MyTool"
                    ),
                ]
            )
            """
        let newContents = try testManifestWritingRoundTrip(manifestContents: manifestContents, toolsVersion: .v5_5, toolsVersionHeaderComment: "a comment")

        XCTAssertTrue(newContents.hasPrefix("// swift-tools-version: 5.5; a comment\n"), "contents: \(newContents)")
    }

    func testAdditionalModuleImports() throws {
        let manifestContents = """
            // swift-tools-version:5.5
            import PackageDescription
            import Foundation

            let package = Package(
                name: "MyPkg",
                targets: [
                    .executableTarget(
                        name: "MyExec"
                    ),
                ]
            )
            """
        let newContents = try testManifestWritingRoundTrip(manifestContents: manifestContents, toolsVersion: .v5_5, additionalImportModuleNames: ["Foundation"])

        XCTAssertTrue(newContents.contains("import Foundation\n"), "contents: \(newContents)")
    }

    func testCustomProductSourceGeneration() throws {
        // Create a manifest containing a product for which we'd like to do custom source fragment generation.
        let manifest = Manifest(
            displayName: "MyLibrary",
            path: AbsolutePath("/tmp/MyLibrary/Package.swift"),
            packageKind: .root(AbsolutePath("/tmp/MyLibrary")),
            packageLocation: "/tmp/MyLibrary",
            platforms: [],
            toolsVersion: .v5_5,
            products: [
                .init(name: "Foo", type: .library(.static), targets: ["Bar"])
            ]
        )

        // Generate the manifest contents, using a custom source generator for the product type.
        let contents = manifest.generateManifestFileContents(customProductTypeSourceGenerator: { product in
            // This example handles library types in a custom way, for testing purposes.
            var params: [SourceCodeFragment] = []
            params.append(SourceCodeFragment(key: "name", string: product.name))
            if !product.targets.isEmpty {
                params.append(SourceCodeFragment(key: "targets", strings: product.targets))
            }
            // Handle .library specially (by not emitting as multiline), otherwise asking for default behavior.
            if case .library(let type) = product.type {
                if type != .automatic {
                    params.append(SourceCodeFragment(key: "type", enum: type.rawValue))
                }
                return SourceCodeFragment(enum: "library", subnodes: params, multiline: false)
            }
            else {
                return nil
            }
        })

        // Check that we generated what we expected.
        XCTAssertTrue(contents.contains(".library(name: \"Foo\", targets: [\"Bar\"], type: .static)"), "contents: \(contents)")
    }

    func testCustomProductTypes() throws {
        // Create a manifest containing a fictional custom product having encoded custom properties.
        let manifest = Manifest(
            displayName: "MyLibrary",
            path: AbsolutePath("/tmp/MyLibrary/Package.swift"),
            packageKind: .root(AbsolutePath("/tmp/MyLibrary")),
            packageLocation: "/tmp/MyLibrary",
            platforms: [],
            toolsVersion: .v5_5,
            products: [
                .init(
                    name: "SampleApp",
                    type: .custom("sample.app-type", Data("{\"identifier\":\"org.me.my-app\",\"version\":42,\"genre\":\"utility\"}".utf8)),
                    targets: []
                )
            ]
        )
        
        // Generate the manifest contents, specifying that that the SampleProductTypes module should be included, and providing a handler for our custom product type.
        let contents = try manifest.generateManifestFileContents(additionalImportModuleNames: ["SampleProductTypes"], customProductTypeSourceGenerator: {
            // Generate a SourceCodeFragement for an instance of our custom product type.
            product in
            
            
            guard case let .custom(customProductTypeName, encodedPropertyData) = product.type else { return nil }
            XCTAssertEqual(customProductTypeName, "sample.app-type")
            
            // This is the struct that's encoded in the product properties.
            struct SampleAppProperties: Codable {
                var identifier: String
                var version: Int
                var genre: Genre
                enum Genre: String, Codable {
                    case design
                    case game
                    case utility
                }
            }
            
            // Decode the product properties.
            let decoder = JSONDecoder()
            let properties = try decoder.decode(SampleAppProperties.self, from: encodedPropertyData)
            
            // Check that we got the expected values.
            XCTAssertEqual(properties.identifier, "org.me.my-app")
            XCTAssertEqual(properties.version, 42)
            XCTAssertEqual(properties.genre, .utility)
            
            // Construct and return a SourceCodeFragment.
            return SourceCodeFragment(enum: "SampleAppType", subnodes: [
                SourceCodeFragment(key: "identifier", string: properties.identifier),
                SourceCodeFragment(key: "version", integer: properties.version),
                SourceCodeFragment(key: "genre", enum: properties.genre.rawValue)
            ], multiline: true)
        })
        
        // Check that we generated what we expected.
        XCTAssertTrue(contents.contains("import SampleProductTypes"), "contents: \(contents)")
        XCTAssertTrue(contents.contains(".SampleAppType("), "contents: \(contents)")
        XCTAssertTrue(contents.contains("identifier: \"org.me.my-app\""), "contents: \(contents)")
        XCTAssertTrue(contents.contains("version: 42"), "contents: \(contents)")
        XCTAssertTrue(contents.contains("genre: .utility"), "contents: \(contents)")
    }
}
