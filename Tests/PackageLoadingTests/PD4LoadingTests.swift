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
import PackageModel
import SPMTestSupport
import PackageLoading

class PackageDescription4LoadingTests: PackageDescriptionLoadingTests {
    override var toolsVersion: ToolsVersion {
        .v4
    }

    func testTrivial() {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
                name: "Trivial"
            )
            """

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.name, "Trivial")
            XCTAssertEqual(manifest.toolsVersion, .v4)
            XCTAssertEqual(manifest.targets, [])
            XCTAssertEqual(manifest.dependencies, [])
        }
    }

    func testTargetDependencies() {
        let stream = BufferedOutputByteStream()
        stream <<< """
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

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.name, "Trivial")
            let targets = Dictionary(uniqueKeysWithValues:
                manifest.targets.map({ ($0.name, $0 as TargetDescription ) }))
            let foo = targets["foo"]!
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

            let bar = targets["bar"]!
            XCTAssertEqual(bar.name, "bar")
            XCTAssertTrue(bar.isTest)
            XCTAssertEqual(bar.dependencies, ["foo"])
        }
    }

    func testCompatibleSwiftVersions() throws {
        var stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               swiftLanguageVersions: [3, 4]
            )
            """
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.swiftLanguageVersions?.map({$0.rawValue}), ["3", "4"])
        }

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
               name: "Foo")
            """
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.swiftLanguageVersions, nil)
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
                   .package(url: "/foo2", .upToNextMajor(from: "1.0.0")),
                   .package(url: "/foo3", .upToNextMinor(from: "1.0.0")),
                   .package(url: "/foo4", .exact("1.0.0")),
                   .package(url: "/foo5", .branch("master")),
                   .package(url: "/foo6", .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")),
               ]
            )
            """
       loadManifest(stream.bytes) { manifest in
            let deps = Dictionary(uniqueKeysWithValues: manifest.dependencies.map{ ($0.url, $0) })
            XCTAssertEqual(deps["/foo1"], PackageDependencyDescription(name: nil, url: "/foo1", requirement: .upToNextMajor(from: "1.0.0")))
            XCTAssertEqual(deps["/foo2"], PackageDependencyDescription(name: nil, url: "/foo2", requirement: .upToNextMajor(from: "1.0.0")))
            XCTAssertEqual(deps["/foo3"], PackageDependencyDescription(name: nil, url: "/foo3", requirement: .upToNextMinor(from: "1.0.0")))
            XCTAssertEqual(deps["/foo4"], PackageDependencyDescription(name: nil, url: "/foo4", requirement: .exact("1.0.0")))
            XCTAssertEqual(deps["/foo5"], PackageDependencyDescription(name: nil, url: "/foo5", requirement: .branch("master")))
            XCTAssertEqual(deps["/foo6"], PackageDependencyDescription(name: nil, url: "/foo6", requirement: .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")))
        }
    }

    func testProducts() {
        let stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo",
               products: [
                   .executable(name: "tool", targets: ["tool"]),
                   .library(name: "Foo", targets: ["Foo"]),
                   .library(name: "FooDy", type: .dynamic, targets: ["Foo"]),
               ]
            )
            """
        loadManifest(stream.bytes) { manifest in
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
        }
    }

    func testSystemPackage() {
        let stream = BufferedOutputByteStream()
        stream <<< """
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
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.name, "Copenssl")
            XCTAssertEqual(manifest.pkgConfig, "openssl")
            XCTAssertEqual(manifest.providers, [
                .brew(["openssl"]),
                .apt(["openssl", "libssl-dev"]),
            ])
        }
    }

    func testCTarget() {
        let stream = BufferedOutputByteStream()
        stream <<< """
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
        loadManifest(stream.bytes) { manifest in
            let targets = Dictionary(uniqueKeysWithValues:
                manifest.targets.map({ ($0.name, $0 as TargetDescription ) }))

            let foo = targets["Foo"]!
            XCTAssertEqual(foo.publicHeadersPath, "inc")

            let bar = targets["Bar"]!
            XCTAssertEqual(bar.publicHeadersPath, nil)
        }
    }

    func testTargetProperties() {
        let stream = BufferedOutputByteStream()
        stream <<< """
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
        loadManifest(stream.bytes) { manifest in
            let targets = Dictionary(uniqueKeysWithValues:
                manifest.targets.map({ ($0.name, $0 as TargetDescription ) }))

            let foo = targets["Foo"]!
            XCTAssertEqual(foo.publicHeadersPath, "inc")
            XCTAssertEqual(foo.path, "foo/z")
            XCTAssertEqual(foo.exclude, ["bar"])
            XCTAssertEqual(foo.sources ?? [], ["bar.swift"])

            let bar = targets["Bar"]!
            XCTAssertEqual(bar.publicHeadersPath, nil)
            XCTAssertEqual(bar.path, nil)
            XCTAssertEqual(bar.exclude, [])
            XCTAssert(bar.sources == nil)
        }
    }

    func testUnavailableAPIs() throws {
        let stream = BufferedOutputByteStream()
        stream.write("""
            import PackageDescription
            let package = Package(
               name: "Foo",
               dependencies: [
                   .package(url: "/foo1", version: "1.0.0"),
                   .package(url: "/foo2", branch: "master"),
                   .package(url: "/foo3", revision: "rev"),
                   .package(url: "/foo4", range: "1.0.0"..<"1.5.0"),
               ]
            )
            """)
        do {
            try loadManifestThrowing(stream.bytes) { manifest in
                XCTFail("this package should not load succesfully")
            }
            XCTFail("this package should not load succesfully")
        } catch ManifestParseError.invalidManifestFormat(let error, _) {
            XCTAssert(error.contains("error: 'package(url:version:)' is unavailable: use package(url:_:) with the .exact(Version) initializer instead\n"))
            XCTAssert(error.contains("error: 'package(url:branch:)' is unavailable: use package(url:_:) with the .branch(String) initializer instead\n"))
            XCTAssert(error.contains("error: 'package(url:revision:)' is unavailable: use package(url:_:) with the .revision(String) initializer instead\n"))
            XCTAssert(error.contains("error: 'package(url:range:)' is unavailable: use package(url:_:) without the range label instead\n"))
        }
    }

    func testLanguageStandards() {
        let stream = BufferedOutputByteStream()
        stream <<< """
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
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.name, "testPackage")
            XCTAssertEqual(manifest.cLanguageStandard, "iso9899:1994")
            XCTAssertEqual(manifest.cxxLanguageStandard, "gnu++14")
        }
    }

    func testManifestWithWarnings() throws {
        let fs = InMemoryFileSystem()
        let manifestPath = AbsolutePath.root.appending(component: Manifest.filename)
        let stream = BufferedOutputByteStream()

        stream <<< """
            import PackageDescription
            func foo() {
                let a = 5
            }
            let package = Package(
                name: "Trivial"
            )
            """

        try fs.writeFileContents(manifestPath, bytes: stream.bytes)

        let diagnostics = DiagnosticsEngine()
        let manifest = try manifestLoader.load(
            package: .root, baseURL: "/foo",
            toolsVersion: .v4, fileSystem: fs,
            diagnostics: diagnostics
        )

        XCTAssertEqual(manifest.name, "Trivial")
        XCTAssertEqual(manifest.toolsVersion, .v4)
        XCTAssertEqual(manifest.targets, [])
        XCTAssertEqual(manifest.dependencies, [])

        DiagnosticsEngineTester(diagnostics) { result in
            result.check(diagnostic: .contains("initialization of immutable value 'a' was never used"), behavior: .warning)
        }
    }
}
