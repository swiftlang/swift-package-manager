//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2017-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageLoading
import PackageModel
import _InternalTestSupport
import XCTest

final class PackageDescription4_0LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v4
    }

    func testTrivial() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Trivial"
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            XCTAssertEqual(manifest.displayName, "Trivial")
            XCTAssertEqual(manifest.toolsVersion, .v4)
            XCTAssertEqual(manifest.targets, [])
            XCTAssertEqual(manifest.dependencies, [])

            return manifest
        }
    }

    func testTargetDependencies() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Trivial",
                targets: [
                    .target(name: "foo", dependencies: [
                        "dep1",
                        .target(name: "dep2"),
                        .product(name: "dep3", package: "Pkg"),
                        .product(name: "dep4"),
                    ]),
                    .testTarget(name: "bar", dependencies: [
                        "foo",
                    ])
                ]
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            XCTAssertEqual(manifest.displayName, "Trivial")
            let foo = manifest.targetMap["foo"]!
            XCTAssertEqual(foo.name, "foo")
            XCTAssertFalse(foo.isTest)

            let expectedDependencies: [TargetDescription.Dependency]
            expectedDependencies = [
                "dep1",
                .target(name: "dep2"),
                .product(name: "dep3", package: "Pkg"),
                .product(name: "dep4"),
            ]
            XCTAssertEqual(foo.dependencies, expectedDependencies)

            let bar = manifest.targetMap["bar"]!
            XCTAssertEqual(bar.name, "bar")
            XCTAssertTrue(bar.isTest)
            XCTAssertEqual(bar.dependencies, ["foo"])
            
            return manifest
        }
    }

    func testCompatibleSwiftVersions() async throws {
        do {
            let content = """
                import PackageDescription
                let package = Package(
                   name: "Foo",
                   swiftLanguageVersions: [3, 4]
                )
                """
            try await forEachManifestLoader { loader in
                let observability = ObservabilitySystem.makeForTesting()
                let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                    content,
                    customManifestLoader: loader,
                    observabilityScope: observability.topScope
                )
                XCTAssertNoDiagnostics(observability.diagnostics)
                XCTAssertNoDiagnostics(validationDiagnostics)
                XCTAssertEqual(manifest.swiftLanguageVersions?.map({$0.rawValue}), ["3", "4"])
                return manifest
            }
        }

        do {
            let content = """
                import PackageDescription
                let package = Package(
                   name: "Foo",
                   swiftLanguageVersions: []
                )
                """
            try await forEachManifestLoader { loader in
                let observability = ObservabilitySystem.makeForTesting()
                let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                    content,
                    customManifestLoader: loader,
                    observabilityScope: observability.topScope
                )
                XCTAssertNoDiagnostics(observability.diagnostics)
                XCTAssertNoDiagnostics(validationDiagnostics)
                XCTAssertEqual(manifest.swiftLanguageVersions, [])
                return manifest
            }
        }

        do {
            let content = """
                import PackageDescription
                let package = Package(
                   name: "Foo")
                """
            try await forEachManifestLoader { loader in
                let observability = ObservabilitySystem.makeForTesting()
                let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                    content,
                    customManifestLoader: loader,
                    observabilityScope: observability.topScope
                )
                XCTAssertNoDiagnostics(observability.diagnostics)
                XCTAssertNoDiagnostics(validationDiagnostics)
                XCTAssertEqual(manifest.swiftLanguageVersions, nil)
                return manifest
            }
        }
    }

    func testPackageDependencies() async throws {
        let content = """
            import PackageDescription
            let package = Package(
               name: "Foo",
               dependencies: [
                   .package(url: "\(AbsolutePath("/foo1").escapedPathString)", from: "1.0.0"),
                   .package(url: "\(AbsolutePath("/foo2").escapedPathString)", .upToNextMajor(from: "1.0.0")),
                   .package(url: "\(AbsolutePath("/foo3").escapedPathString)", .upToNextMinor(from: "1.0.0")),
                   .package(url: "\(AbsolutePath("/foo4").escapedPathString)", .exact("1.0.0")),
                   .package(url: "\(AbsolutePath("/foo5").escapedPathString)", .branch("main")),
                   .package(url: "\(AbsolutePath("/foo6").escapedPathString)", .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")),
               ]
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.identity.description, $0) })
            XCTAssertEqual(deps["foo1"], .localSourceControl(path: "/foo1", requirement: .upToNextMajor(from: "1.0.0")))
            XCTAssertEqual(deps["foo2"], .localSourceControl(path: "/foo2", requirement: .upToNextMajor(from: "1.0.0")))
            XCTAssertEqual(deps["foo3"], .localSourceControl(path: "/foo3", requirement: .upToNextMinor(from: "1.0.0")))
            XCTAssertEqual(deps["foo4"], .localSourceControl(path: "/foo4", requirement: .exact("1.0.0")))
            XCTAssertEqual(deps["foo5"], .localSourceControl(path: "/foo5", requirement: .branch("main")))
            XCTAssertEqual(deps["foo6"], .localSourceControl(path: "/foo6", requirement: .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")))
            
            return manifest
        }
    }

    func testProducts() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "Foo",
                products: [
                    .executable(name: "tool", targets: ["tool"]),
                    .library(name: "Foo", targets: ["Foo"]),
                    .library(name: "FooDy", type: .dynamic, targets: ["Foo"]),
                ],
                targets: [
                    .target(name: "Foo"),
                    .target(name: "tool"),
                ]
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            let products = Dictionary(uniqueKeysWithValues: manifest.products.map{ ($0.name, $0) })
            // Check tool.
            let tool = products["tool"]!
            XCTAssertEqual(tool.name, "tool")
            XCTAssertEqual(tool.targets, ["tool"])
            XCTAssertEqual(tool.type, .executable)
            // Check Foo.
            let foo = products["Foo"]!
            XCTAssertEqual(foo.name, "Foo")
            XCTAssertEqual(foo.type, .library(.automatic))
            XCTAssertEqual(foo.targets, ["Foo"])
            // Check FooDy.
            let fooDy = products["FooDy"]!
            XCTAssertEqual(fooDy.name, "FooDy")
            XCTAssertEqual(fooDy.type, .library(.dynamic))
            XCTAssertEqual(fooDy.targets, ["Foo"])
            
            return manifest
        }
    }

    func testSystemPackage() async throws {
        let content = """
            import PackageDescription
            let package = Package(
               name: "Copenssl",
               pkgConfig: "openssl",
               providers: [
                   .brew(["openssl"]),
                   .apt(["openssl", "libssl-dev"]),
               ]
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            XCTAssertEqual(manifest.displayName, "Copenssl")
            XCTAssertEqual(manifest.pkgConfig, "openssl")
            XCTAssertEqual(manifest.providers, [
                .brew(["openssl"]),
                .apt(["openssl", "libssl-dev"]),
            ])
            
            return manifest
        }
    }

    func testCTarget() async throws {
        let content = """
            import PackageDescription
            let package = Package(
               name: "libyaml",
               targets: [
                   .target(
                       name: "Foo",
                       publicHeadersPath: "inc"),
                   .target(
                   name: "Bar"),
               ]
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            let foo = manifest.targetMap["Foo"]!
            XCTAssertEqual(foo.publicHeadersPath, "inc")

            let bar = manifest.targetMap["Bar"]!
            XCTAssertEqual(bar.publicHeadersPath, nil)
            
            return manifest
        }
    }

    func testTargetProperties() async throws {
        let content = """
            import PackageDescription
            let package = Package(
               name: "libyaml",
               targets: [
                   .target(
                       name: "Foo",
                       path: "foo/z",
                       exclude: ["bar"],
                       sources: ["bar.swift"],
                       publicHeadersPath: "inc"),
                   .target(
                   name: "Bar"),
               ]
            )
            """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            let foo = manifest.targetMap["Foo"]!
            XCTAssertEqual(foo.publicHeadersPath, "inc")
            XCTAssertEqual(foo.path, "foo/z")
            XCTAssertEqual(foo.exclude, ["bar"])
            XCTAssertEqual(foo.sources ?? [], ["bar.swift"])

            let bar = manifest.targetMap["Bar"]!
            XCTAssertEqual(bar.publicHeadersPath, nil)
            XCTAssertEqual(bar.path, nil)
            XCTAssertEqual(bar.exclude, [])
            XCTAssert(bar.sources == nil)
            
            return manifest
        }
    }

    func testUnavailableAPIs() async throws {
        let content = """
            import PackageDescription
            let package = Package(
               name: "Foo",
               dependencies: [
                   .package(url: "/foo1", version: "1.0.0"),
                   .package(url: "/foo2", branch: "main"),
                   .package(url: "/foo3", revision: "rev"),
                   .package(url: "/foo4", range: "1.0.0"..<"1.5.0"),
               ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        await XCTAssertAsyncThrowsError(try await loadAndValidateManifest(content, observabilityScope: observability.topScope), "expected error") { error in
            if case ManifestParseError.invalidManifestFormat(let error, _, _) = error {
                XCTAssert(error.contains("error: 'package(url:version:)' is unavailable: use package(url:exact:) instead"), "\(error)")
                XCTAssert(error.contains("error: 'package(url:range:)' is unavailable: use package(url:_:) instead"), "\(error)")
            } else {
                XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testLanguageStandards() async throws {
        let content = """
            import PackageDescription
            let package = Package(
                name: "testPackage",
                targets: [
                    .target(name: "Foo"),
                ],
                cLanguageStandard: .iso9899_199409,
                cxxLanguageStandard: .gnucxx14
            )
        """

        try await forEachManifestLoader { loader in
            let observability = ObservabilitySystem.makeForTesting()
            let (manifest, validationDiagnostics) = try await loadAndValidateManifest(
                content,
                customManifestLoader: loader,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)
            XCTAssertNoDiagnostics(validationDiagnostics)

            XCTAssertEqual(manifest.displayName, "testPackage")
            XCTAssertEqual(manifest.cLanguageStandard, "iso9899:199409")
            XCTAssertEqual(manifest.cxxLanguageStandard, "gnu++14")
            
            return manifest
        }
    }

    func testManifestWithWarnings() async throws {
        let fs = InMemoryFileSystem()
        let manifestPath = AbsolutePath.root.appending(component: Manifest.filename)

        let content = """
            import PackageDescription
            func foo() {
                let a = 5
            }
            let package = Package(
                name: "Trivial"
            )
            """

        try fs.writeFileContents(manifestPath, string: content)

        let observability = ObservabilitySystem.makeForTesting()
        let manifest = try await manifestLoader.load(
            manifestPath: manifestPath,
            packageKind: .root(.root),
            toolsVersion: .v4,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        XCTAssertEqual(manifest.displayName, "Trivial")
        XCTAssertEqual(manifest.toolsVersion, .v4)
        XCTAssertEqual(manifest.targets, [])
        XCTAssertEqual(manifest.dependencies, [])

        testDiagnostics(observability.diagnostics) { result in
            result.check(diagnostic: .contains("initialization of immutable value 'a' was never used"), severity: .warning)
        }
    }

    func testDuplicateTargets() async throws {
        let content = """
            import PackageDescription

            let package = Package(
                name: "Foo",
                targets: [
                    .target(name: "A"),
                    .target(name: "B"),
                    .target(name: "A"),
                    .target(name: "B"),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (_, validationDiagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
        testDiagnostics(validationDiagnostics) { result in
            result.checkUnordered(diagnostic: "duplicate target named 'A'", severity: .error)
            result.checkUnordered(diagnostic: "duplicate target named 'B'", severity: .error)
        }
    }

    func testEmptyProductTargets() async throws {
        let content = """
            import PackageDescription

            let package = Package(
                name: "Foo",
                products: [
                    .library(name: "Product", targets: []),
                ],
                targets: [
                    .target(name: "Target"),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (_, validationDiagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
        testDiagnostics(validationDiagnostics) { result in
            result.check(diagnostic: "product 'Product' doesn't reference any targets", severity: .error)
        }
    }

    func testProductTargetNotFound() async throws {
        let content = """
            import PackageDescription

            let package = Package(
                name: "Foo",
                products: [
                    .library(name: "Product", targets: ["A", "B"]),
                ],
                targets: [
                    .target(name: "A"),
                ]
            )
            """

        let observability = ObservabilitySystem.makeForTesting()
        let (_, validationDiagnostics) = try await loadAndValidateManifest(content, observabilityScope: observability.topScope)
        XCTAssertNoDiagnostics(observability.diagnostics)
        testDiagnostics(validationDiagnostics) { result in
            result.check(diagnostic: "target 'B' referenced in product 'Product' could not be found; valid targets are: 'A'", severity: .error)
        }
    }

    // Test the legacy system library package style: a package with pkgConfig
    // (and optionally providers) at the Package level and a module.modulemap
    // file on disk, but no explicit targets or products in the manifest. Both
    // loaders must synthesize an equivalent system library target and product.
    func testLegacySystemLibraryPackage() async throws {
        let content = """
            // swift-tools-version:4.0
            import PackageDescription
            let package = Package(
                name: "CZLib",
                pkgConfig: "zlib",
                providers: [
                    .brew(["zlib"]),
                    .apt(["zlib1g-dev"]),
                ]
            )
            """

        for loader in self.testManifestLoaders {
            let packagePath = AbsolutePath.root
            let manifestPath = packagePath.appending(component: Manifest.filename)
            let fileSystem = InMemoryFileSystem()
            try fileSystem.writeFileContents(manifestPath, string: content)
            // The presence of module.modulemap triggers the legacy system library path.
            try fileSystem.writeFileContents(
                packagePath.appending(component: "module.modulemap"),
                string: "module CZLib { header \"zlib.h\" }"
            )

            let observability = ObservabilitySystem.makeForTesting()
            let manifest = try await (loader ?? self.manifestLoader).load(
                manifestPath: manifestPath,
                packageKind: .fileSystem(packagePath),
                toolsVersion: .v4,
                fileSystem: fileSystem,
                observabilityScope: observability.topScope
            )
            XCTAssertNoDiagnostics(observability.diagnostics)

            // The parser must synthesize a system library target and product.
            XCTAssertEqual(manifest.targets.count, 1)
            let target = try XCTUnwrap(manifest.targets.first)
            XCTAssertEqual(target.name, "CZLib")
            XCTAssertEqual(target.type, .system)
            XCTAssertEqual(target.pkgConfig, "zlib")
            XCTAssertEqual(target.providers, [.brew(["zlib"]), .apt(["zlib1g-dev"])])
            XCTAssertEqual(target.packageAccess, false)

            XCTAssertEqual(manifest.products.count, 1)
            let product = try XCTUnwrap(manifest.products.first)
            XCTAssertEqual(product.name, "CZLib")
            XCTAssertEqual(product.type, .library(.automatic))
            XCTAssertEqual(product.targets, ["CZLib"])

            // Package-level pkgConfig/providers must still be present.
            XCTAssertEqual(manifest.pkgConfig, "zlib")
            XCTAssertEqual(manifest.providers, [.brew(["zlib"]), .apt(["zlib1g-dev"])])
        }
    }

    // Without a module.modulemap on disk the manifest must NOT synthesize a
    // system library target, even when pkgConfig is set at the package level.
    func testLegacySystemLibraryPackageWithoutModuleMap() async throws {
        let content = """
            // swift-tools-version:4.0
            import PackageDescription
            let package = Package(
                name: "CZLib",
                pkgConfig: "zlib"
            )
            """

        // No module.modulemap on disk — let loadAndValidateManifest create a
        // minimal filesystem with only the manifest file.
        let observability = ObservabilitySystem.makeForTesting()
        let (manifest, _) = try await loadAndValidateManifest(
            content,
            customManifestLoader: self.parsingManifestLoader,
            observabilityScope: observability.topScope
        )
        XCTAssertNoDiagnostics(observability.diagnostics)
        // No targets or products should be synthesized.
        XCTAssertEqual(manifest.targets.count, 0)
        XCTAssertEqual(manifest.products.count, 0)
        XCTAssertEqual(manifest.pkgConfig, "zlib")
    }
}

