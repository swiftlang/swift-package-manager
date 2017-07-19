/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import Utility

import PackageDescription4
import PackageModel
import TestSupport

import PackageLoading

class PackageDescription4LoadingTests: XCTestCase {
    let manifestLoader = ManifestLoader(resources: Resources.default)

    private func loadManifestThrowing(
        _ contents: ByteString,
        line: UInt = #line,
        body: (Manifest) -> Void) throws
    {
        let fs = InMemoryFileSystem()
        let manifestPath = AbsolutePath.root.appending(component: Manifest.filename)
        try fs.writeFileContents(manifestPath, bytes: contents)
        let m = try manifestLoader.load(
            package: AbsolutePath.root,
            baseURL: AbsolutePath.root.asString,
            manifestVersion: .four,
            fileSystem: fs)
        if case .v4 = m.package {} else {
            return XCTFail("Invalid manfiest version")
        }
        body(m)
    }

    private func loadManifest(
        _ contents: ByteString,
        line: UInt = #line,
        body: (Manifest) -> Void)
    {
        do {
            try loadManifestThrowing(contents, line: line, body: body)
        } catch ManifestParseError.invalidManifestFormat(let error) {
            print(error)
            XCTFail(file: #file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: #file, line: line)
        }
    }

    func testManiestVersionToToolsVersion() {
        let threeVersions = [
            "3.0.0", "3.0.1", "3.0.10", "3.1.0", "3.1.100", "3.5", "3.9.9999",
        ]

        for version in threeVersions {
            let toolsVersion = ToolsVersion(string: version)!
            XCTAssertEqual(toolsVersion.manifestVersion, .three)
        }

        let fourVersions = [
            "2.0.0", "4.0.0", "4.0.10", "5.1.0", "6.1.100", "4.3",
        ]

        for version in fourVersions {
            let toolsVersion = ToolsVersion(string: version)!
            XCTAssertEqual(toolsVersion.manifestVersion, .four)
        }
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
            XCTAssertEqual(manifest.manifestVersion, .four)
            XCTAssertEqual(manifest.package.targets, [])
            XCTAssertEqual(manifest.package.dependencies, [])
            let flags = manifest.interpreterFlags.joined(separator: " ")
            XCTAssertTrue(flags.contains("/swift/pm/4"))
            XCTAssertTrue(flags.contains("-swift-version 4"))
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
            let targets = Dictionary(items:
                manifest.package.targets.map({ ($0.name, $0 as PackageDescription4.Target ) }))
            let foo = targets["foo"]!
            XCTAssertEqual(foo.name, "foo")
            XCTAssertFalse(foo.isTest)

            let expectedDependencies: [PackageDescription4.Target.Dependency]
            expectedDependencies = [
                .byName(name: "dep1"),
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
            XCTAssertEqual(manifest.package.swiftLanguageVersions ?? [], [3, 4])
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
            XCTAssertEqual(manifest.package.swiftLanguageVersions!, [])
        }

        stream = BufferedOutputByteStream()
        stream <<< """
            import PackageDescription
            let package = Package(
               name: "Foo")
            """
        loadManifest(stream.bytes) { manifest in
            XCTAssert(manifest.package.swiftLanguageVersions == nil)
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
            let deps = Dictionary(items: manifest.package.dependencies.map{ ($0.url, $0) })
            XCTAssertEqual(deps["/foo1"], .package(url: "/foo1", from: "1.0.0"))
            XCTAssertEqual(deps["/foo2"], .package(url: "/foo2", .upToNextMajor(from: "1.0.0")))
            XCTAssertEqual(deps["/foo3"], .package(url: "/foo3", .upToNextMinor(from: "1.0.0")))
            XCTAssertEqual(deps["/foo4"], .package(url: "/foo4", .exact("1.0.0")))
            XCTAssertEqual(deps["/foo5"], .package(url: "/foo5", .branch("master")))
            XCTAssertEqual(deps["/foo6"], .package(url: "/foo6", .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")))
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
            guard case .v4(let package) = manifest.package else {
                return XCTFail()
            }
            let products = Dictionary(items: package.products.map{ ($0.name, $0) })
            // Check tool.
            let tool = products["tool"]! as! PackageDescription4.Product.Executable
            XCTAssertEqual(tool.name, "tool")
            XCTAssertEqual(tool.targets, ["tool"])
            // Check Foo.
            let foo = products["Foo"]! as! PackageDescription4.Product.Library
            XCTAssertEqual(foo.name, "Foo")
            XCTAssertEqual(foo.type, nil)
            XCTAssertEqual(foo.targets, ["Foo"])
            // Check FooDy.
            let fooDy = products["FooDy"]! as! PackageDescription4.Product.Library
            XCTAssertEqual(fooDy.name, "FooDy")
            XCTAssertEqual(fooDy.type, .dynamic)
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
            XCTAssertEqual(manifest.package.pkgConfig, "openssl")
            XCTAssertEqual(manifest.package.providers!, [
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
            let targets = Dictionary(items:
                manifest.package.targets.map({ ($0.name, $0 as PackageDescription4.Target ) }))

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
            let targets = Dictionary(items:
                manifest.package.targets.map({ ($0.name, $0 as PackageDescription4.Target ) }))

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
        } catch ManifestParseError.invalidManifestFormat(let error) {
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
            XCTAssertEqual(manifest.package.name, "testPackage")
            XCTAssertEqual(manifest.package.cLanguageStandard, .iso9899_199409)
            XCTAssertEqual(manifest.package.cxxLanguageStandard, .gnucxx14)
        }
    }

    static var allTests = [
        ("testCTarget", testCTarget),
        ("testCompatibleSwiftVersions", testCompatibleSwiftVersions),
        ("testManiestVersionToToolsVersion", testManiestVersionToToolsVersion),
        ("testPackageDependencies", testPackageDependencies),
        ("testProducts", testProducts),
        ("testSystemPackage", testSystemPackage),
        ("testTargetDependencies", testTargetDependencies),
        ("testTargetProperties", testTargetProperties),
        ("testTrivial", testTrivial),
        ("testUnavailableAPIs", testUnavailableAPIs),
        ("testLanguageStandards", testLanguageStandards),
    ]
}
