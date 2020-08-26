/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import TSCUtility
import SPMTestSupport
import PackageModel
import PackageLoading

class PackageDescription4_2LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v4_2
    }

    func testBasics() {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Trivial",
                products: [
                    .executable(name: "tool", targets: ["tool"]),
                    .library(name: "Foo", targets: ["foo"]),
                ],
                dependencies: [
                    .package(url: "/foo1", from: "1.0.0"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: ["dep1", .product(name: "product"), .target(name: "target")]),
                    .target(
                        name: "tool"),
                    .testTarget(
                        name: "bar",
                        dependencies: ["foo"]),
                ]
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.name, "Trivial")

            // Check targets.
            let foo = manifest.targetMap["foo"]!
            XCTAssertEqual(foo.name, "foo")
            XCTAssertFalse(foo.isTest)
            XCTAssertEqual(foo.dependencies, ["dep1", .product(name: "product"), .target(name: "target")])

            let bar = manifest.targetMap["bar"]!
            XCTAssertEqual(bar.name, "bar")
            XCTAssertTrue(bar.isTest)
            XCTAssertEqual(bar.dependencies, ["foo"])

            // Check dependencies.
            let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.url, $0) })
            XCTAssertEqual(deps["/foo1"], PackageDependencyDescription(name: nil, url: "/foo1", requirement: .upToNextMajor(from: "1.0.0")))

            // Check products.
            let products = Dictionary(uniqueKeysWithValues: manifest.products.map{ ($0.name, $0) })

            let tool = products["tool"]!
            XCTAssertEqual(tool.name, "tool")
            XCTAssertEqual(tool.targets, ["tool"])
            XCTAssertEqual(tool.type, .executable)

            let fooProduct = products["Foo"]!
            XCTAssertEqual(fooProduct.name, "Foo")
            XCTAssertEqual(fooProduct.type, .library(.automatic))
            XCTAssertEqual(fooProduct.targets, ["foo"])
        }
    }

    func testSwiftLanguageVersions() throws {
        // Ensure integer values are not accepted.
        var stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               swiftLanguageVersions: [3, 4]
            )
            """

        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail()
        } catch {
            guard case let ManifestParseError.invalidManifestFormat(output, _) = error else {
                return XCTFail()
            }
            XCTAssertMatch(output, .and(.or(.contains("expected argument type"), .contains("expected element type")), .contains("SwiftVersion")))
        }

        // Check when Swift language versions is empty.
        stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               swiftLanguageVersions: []
            )
            """
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.swiftLanguageVersions, [])
        }

        stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               swiftLanguageVersions: [.v3, .v4, .v4_2, .version("5")]
            )
            """
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(
                manifest.swiftLanguageVersions,
                [.v3, .v4, .v4_2, SwiftLanguageVersion(string: "5")!]
            )
        }

        stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               swiftLanguageVersions: [.v5]
            )
            """

        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail()
        } catch {
            guard case let ManifestParseError.invalidManifestFormat(message, _) = error else {
                return XCTFail("\(error)")
            }

            XCTAssertMatch(message, .contains("is unavailable"))
            XCTAssertMatch(message, .contains("was introduced in PackageDescription 5"))
        }
    }

    func testPlatforms() throws {
        var stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               platforms: nil
            )
            """

        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail()
        } catch {
            guard case let ManifestParseError.invalidManifestFormat(message, _) = error else {
                return XCTFail("\(error)")
            }

            XCTAssertMatch(message, .contains("is unavailable"))
            XCTAssertMatch(message, .contains("was introduced in PackageDescription 5"))
        }

        stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               platforms: [.macOS(.v10_10)]
            )
            """

        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail()
        } catch {
            guard case let ManifestParseError.invalidManifestFormat(message, _) = error else {
                return XCTFail("\(error)")
            }

            XCTAssertMatch(message, .contains("is unavailable"))
            XCTAssertMatch(message, .contains("was introduced in PackageDescription 5"))
        }
    }

    func testBuildSettings() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               targets: [
                   .target(
                       name: "Foo",
                       swiftSettings: [
                           .define("SWIFT", .when(configuration: .release)),
                       ],
                       linkerSettings: [
                           .linkedLibrary("libz"),
                       ]
                   ),
               ]
            )
            """

        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail()
        } catch {
            guard case let ManifestParseError.invalidManifestFormat(message, _) = error else {
                return XCTFail("\(error)")
            }

            XCTAssertMatch(message, .contains("is unavailable"))
            XCTAssertMatch(message, .contains("was introduced in PackageDescription 5"))
        }
    }

    func testPackageDependencies() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
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
               ]
            )
            """
       loadManifest(stream.bytes) { manifest in
            let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.url, $0) })
            XCTAssertEqual(deps["/foo1"], PackageDependencyDescription(name: nil, url: "/foo1", requirement: .upToNextMajor(from: "1.0.0")))
            XCTAssertEqual(deps["/foo2"], PackageDependencyDescription(name: nil, url: "/foo2", requirement: .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")))

            XCTAssertEqual(deps["/foo3"]?.url, "/foo3")
            XCTAssertEqual(deps["/foo3"]?.requirement, .localPackage)

            XCTAssertEqual(deps["/path/to/foo4"]?.url, "/path/to/foo4")
            XCTAssertEqual(deps["/path/to/foo4"]?.requirement, .localPackage)

            XCTAssertEqual(deps["/foo5"], PackageDependencyDescription(name: nil, url: "/foo5", requirement: .exact("1.2.3")))
            XCTAssertEqual(deps["/foo6"], PackageDependencyDescription(name: nil, url: "/foo6", requirement: .range("1.2.3"..<"2.0.0")))
            XCTAssertEqual(deps["/foo7"], PackageDependencyDescription(name: nil, url: "/foo7", requirement: .branch("master")))
            XCTAssertEqual(deps["/foo8"], PackageDependencyDescription(name: nil, url: "/foo8", requirement: .upToNextMinor(from: "1.3.4")))
            XCTAssertEqual(deps["/foo9"], PackageDependencyDescription(name: nil, url: "/foo9", requirement: .upToNextMajor(from: "1.3.4")))

            let homeDir = "/home/user"
            XCTAssertEqual(deps["\(homeDir)/path/to/foo10"]?.url, "\(homeDir)/path/to/foo10")
            XCTAssertEqual(deps["\(homeDir)/path/to/foo10"]?.requirement, .localPackage)

            XCTAssertEqual(deps["/foo/~foo11"]?.url, "/foo/~foo11")
            XCTAssertEqual(deps["/foo/~foo11"]?.requirement, .localPackage)

            XCTAssertEqual(deps["\(homeDir)/path/to/~/foo12"]?.url, "\(homeDir)/path/to/~/foo12")
            XCTAssertEqual(deps["\(homeDir)/path/to/~/foo12"]?.requirement, .localPackage)

            XCTAssertEqual(deps["/foo/~"]?.url, "/foo/~")
            XCTAssertEqual(deps["/foo/~"]?.requirement, .localPackage)
        }
    }

    func testSystemLibraryTargets() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
                targets: [
                    .target(
                        name: "foo",
                        dependencies: ["bar"]),
                    .systemLibrary(
                        name: "bar",
                        pkgConfig: "libbar",
                        providers: [
                            .brew(["libgit"]),
                            .apt(["a", "b"]),
                        ]),
                ]
            )
            """
       loadManifest(stream.bytes) { manifest in
            let foo = manifest.targetMap["foo"]!
            XCTAssertEqual(foo.name, "foo")
            XCTAssertFalse(foo.isTest)
            XCTAssertEqual(foo.type, .regular)
            XCTAssertEqual(foo.dependencies, ["bar"])

            let bar = manifest.targetMap["bar"]!
            XCTAssertEqual(bar.name, "bar")
            XCTAssertEqual(bar.type, .system)
            XCTAssertEqual(bar.pkgConfig, "libbar")
            XCTAssertEqual(bar.providers, [.brew(["libgit"]), .apt(["a", "b"])])
        }
    }

    /// Check that we load the manifest appropriate for the current version, if
    /// version specific customization is used.
    func testVersionSpecificLoading() throws {
        let bogusManifest: ByteString = "THIS WILL NOT PARSE"
        let trivialManifest = ByteString(encodingAsUTF8: (
                "import PackageDescription\n" +
                "let package = Package(name: \"Trivial\")"))

        // Check at each possible spelling.
        let currentVersion = Versioning.currentVersion
        let possibleSuffixes = [
            "\(currentVersion.major).\(currentVersion.minor).\(currentVersion.patch)",
            "\(currentVersion.major).\(currentVersion.minor)",
            "\(currentVersion.major)"
        ]
        for (i, key) in possibleSuffixes.enumerated() {
            let root = AbsolutePath.root
            // Create a temporary FS with the version we want to test, and everything else as bogus.
            let fs = InMemoryFileSystem()
            // Write the good manifests.
            try fs.writeFileContents(
                root.appending(component: Manifest.basename + "@swift-\(key).swift"),
                bytes: trivialManifest)
            // Write the bad manifests.
            let badManifests = [Manifest.filename] + possibleSuffixes[i+1 ..< possibleSuffixes.count].map{
                Manifest.basename + "@swift-\($0).swift"
            }
            try badManifests.forEach {
                try fs.writeFileContents(
                    root.appending(component: $0),
                    bytes: bogusManifest)
            }
            // Check we can load the repository.
            let manifest = try manifestLoader.load(package: root, baseURL: "/foo", toolsVersion: .v4_2, packageKind: .root, fileSystem: fs)
            XCTAssertEqual(manifest.name, "Trivial")
        }
    }

    func testRuntimeManifestErrors() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Trivial",
                products: [
                    .executable(name: "tool", targets: ["tool"]),
                    .library(name: "Foo", targets: ["Foo"]),
                ],
                dependencies: [
                    .package(url: "/foo1", from: "1.0,0"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: ["dep1", .product(name: "product"), .target(name: "target")]),
                    .testTarget(
                        name: "bar",
                        dependencies: ["foo"]),
                ]
            )
            """


        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail("Unexpected success")
        } catch ManifestParseError.runtimeManifestErrors(let errors) {
            XCTAssertEqual(errors, ["Invalid semantic version string '1.0,0'"])
        }
    }

    func testDuplicateDependencyDecl() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Trivial",
                dependencies: [
                    .package(path: "../foo1"),
                    .package(url: "/foo1.git", from: "1.0.1"),
                    .package(url: "path/to/foo1", from: "3.0.0"),
                    .package(url: "/foo2.git", from: "1.0.1"),
                    .package(url: "/foo2.git", from: "1.1.1"),
                    .package(url: "/foo3.git", from: "1.0.1"),
                ],
                targets: [
                    .target(
                        name: "foo",
                        dependencies: ["dep1", .target(name: "target")]),
                ]
            )
            """

        XCTAssertManifestLoadThrows(stream.bytes) { _, diagnostics in
            diagnostics.check(diagnostic: .regex("duplicate dependency 'foo(1|2)'"), behavior: .error)
            diagnostics.check(diagnostic: .regex("duplicate dependency 'foo(1|2)'"), behavior: .error)
        }
    }

    func testNotAbsoluteDependencyPath() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
        import PackageDescription
        let package = Package(
            name: "Trivial",
            dependencies: [
                .package(path: "https://someurl.com"),
            ],
            targets: [
                .target(
                    name: "foo",
                    dependencies: []),
            ]
        )
        """

        do {
            try loadManifestThrowing(stream.bytes) { _ in }
            XCTFail("Unexpected success")
        } catch ManifestParseError.invalidManifestFormat(let message, let diagnosticFile) {
            XCTAssertNil(diagnosticFile)
            XCTAssertEqual(message, "'https://someurl.com' is not a valid path for path-based dependencies; use relative or absolute path instead.")
        }
    }

    func testCacheInvalidationOnEnv() {
        mktmpdir { path in
            let fs = localFileSystem

            let manifestPath = path.appending(components: "pkg", "Package.swift")
            try fs.writeFileContents(manifestPath) { stream in
                stream <<< """
                    import PackageDescription
                    let package = Package(
                        name: "Trivial",
                        targets: [
                            .target(
                                name: "foo",
                                dependencies: []),
                        ]
                    )
                    """
            }

            let delegate = ManifestTestDelegate()

            let manifestLoader = ManifestLoader(
                manifestResources: Resources.default, cacheDir: path, delegate: delegate)

            func check(loader: ManifestLoader, expectCached: Bool) {
                delegate.clear()
                let manifest = try! loader.load(
                    package: manifestPath.parentDirectory,
                    baseURL: manifestPath.pathString,
                    toolsVersion: .v4_2,
                    packageKind: .local
                )

                XCTAssertEqual(delegate.loaded, [manifestPath])
                XCTAssertEqual(delegate.parsed, expectCached ? [] : [manifestPath])
                XCTAssertEqual(manifest.name, "Trivial")
                XCTAssertEqual(manifest.targets[0].name, "foo")
            }

            check(loader: manifestLoader, expectCached: false)
            check(loader: manifestLoader, expectCached: true)

            try withCustomEnv(["SWIFTPM_MANIFEST_CACHE_TEST": "1"]) {
                check(loader: manifestLoader, expectCached: false)
                check(loader: manifestLoader, expectCached: true)
            }

            try withCustomEnv(["SWIFTPM_MANIFEST_CACHE_TEST": "2"]) {
                check(loader: manifestLoader, expectCached: false)
                check(loader: manifestLoader, expectCached: true)
            }

            check(loader: manifestLoader, expectCached: true)
        }
    }

    func testCaching() {
        mktmpdir { path in
            let fs = localFileSystem

            let manifestPath = path.appending(components: "pkg", "Package.swift")
            try fs.writeFileContents(manifestPath) { stream in
                stream <<< """
                    import PackageDescription
                    let package = Package(
                        name: "Trivial",
                        targets: [
                            .target(
                                name: "foo",
                                dependencies: []),
                        ]
                    )
                    """
            }

            let delegate = ManifestTestDelegate()

            let manifestLoader = ManifestLoader(
                manifestResources: Resources.default, cacheDir: path, delegate: delegate)

            func check(loader: ManifestLoader, expectCached: Bool) {
                delegate.clear()
                let manifest = try! loader.load(
                    package: manifestPath.parentDirectory,
                    baseURL: manifestPath.pathString,
                    toolsVersion: .v4_2,
                    packageKind: .local
                )

                XCTAssertEqual(delegate.loaded, [manifestPath])
                XCTAssertEqual(delegate.parsed, expectCached ? [] : [manifestPath])
                XCTAssertEqual(manifest.name, "Trivial")
                XCTAssertEqual(manifest.targets[0].name, "foo")
            }

            check(loader: manifestLoader, expectCached: false)
            for _ in 0..<2 {
                check(loader: manifestLoader, expectCached: true)
            }

            try fs.writeFileContents(manifestPath) { stream in
                stream <<< """
                    import PackageDescription

                    let package = Package(

                        name: "Trivial",
                        targets: [
                            .target(
                                name: "foo",
                                dependencies: [  ]),
                        ]
                    )

                    """
            }

            check(loader: manifestLoader, expectCached: false)
            for _ in 0..<2 {
                check(loader: manifestLoader, expectCached: true)
            }

            let noCacheLoader = ManifestLoader(
                manifestResources: Resources.default, delegate: delegate)
            for _ in 0..<2 {
                check(loader: noCacheLoader, expectCached: false)
            }

            // Resetting the cache should allow us to remove the cache
            // directory without triggering assertions in sqlite.
            try manifestLoader.resetCache()
            try localFileSystem.removeFileTree(path)
        }
    }

    func testContentBasedCaching() throws {
        mktmpdir { path in
            let stream = BufferedOutputByteStream()
            stream <<< """
                import PackageDescription
                let package = Package(
                    name: "Trivial",
                    targets: [
                        .target(name: "foo"),
                    ]
                )
                """

            let delegate = ManifestTestDelegate()

            let manifestLoader = ManifestLoader(
                manifestResources: Resources.default, cacheDir: path, delegate: delegate)

            func check(loader: ManifestLoader) throws {
                let fs = InMemoryFileSystem()
                let manifestPath = AbsolutePath.root.appending(component: Manifest.filename)
                try fs.writeFileContents(manifestPath, bytes: stream.bytes)

                let m = try manifestLoader.load(
                    package: AbsolutePath.root,
                    baseURL: "/foo",
                    toolsVersion: .v4_2,
                    packageKind: .root,
                    fileSystem: fs)

                XCTAssertEqual(m.name, "Trivial")
            }

            try check(loader: manifestLoader)
            XCTAssertEqual(delegate.loaded.count, 1)
            XCTAssertEqual(delegate.parsed.count, 1)

            try check(loader: manifestLoader)
            XCTAssertEqual(delegate.loaded.count, 2)
            XCTAssertEqual(delegate.parsed.count, 1)

            stream <<< "\n\n"
            try check(loader: manifestLoader)
            XCTAssertEqual(delegate.loaded.count, 3)
            XCTAssertEqual(delegate.parsed.count, 2)
        }
    }

    func testProductTargetNotFound() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription

            let package = Package(
                name: "Foo",
                products: [
                    .library(name: "Product", targets: ["B"]),
                ],
                targets: [
                    .target(name: "A"),
                ]
            )
            """

        XCTAssertManifestLoadThrows(stream.bytes) { _, diagnostics in
            diagnostics.check(diagnostic: "target 'B' referenced in product 'Product' could not be found", behavior: .error)
        }
    }

    func testLoadingWithoutDiagnostics() throws {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription

            let package = Package(
                name: "Foo",
                products: [
                    .library(name: "Product", targets: ["B"]),
                ],
                targets: [
                    .target(name: "A"),
                ]
            )
            """

        do {
            _ = try loadManifest(
                stream.bytes,
                toolsVersion: toolsVersion,
                packageKind: .remote,
                diagnostics: nil
            )

            XCTFail("Unexpected success")
        } catch let error as StringError {
            XCTAssertMatch(error.description, "target 'B' referenced in product 'Product' could not be found")
        }
    }

    final class ManifestTestDelegate: ManifestLoaderDelegate {
        var loaded: [AbsolutePath] = []
        var parsed: [AbsolutePath] = []

        func willLoad(manifest: AbsolutePath) {
            loaded.append(manifest)
        }

        func willParse(manifest: AbsolutePath) {
            parsed.append(manifest)
        }

        func clear() {
            loaded.removeAll()
            parsed.removeAll()
        }
    }
}
