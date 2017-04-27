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

    private func loadManifest(
        _ contents: ByteString,
        line: UInt = #line,
        body: (Manifest) -> Void
    ) {
        do {
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
        stream <<< "import PackageDescription" <<< "\n"
        stream <<< "let package = Package(" <<< "\n"
        stream <<< "    name: \"Trivial\"" <<< "\n"
        stream <<< ")" <<< "\n"

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
        stream <<< "import PackageDescription\n"
        stream <<< "let package = Package("
        stream <<< "    name: \"Trivial\","
        stream <<< "    targets: ["
        stream <<< "        .target("
        stream <<< "            name: \"foo\","
        stream <<< "            dependencies: ["
        stream <<< "                \"dep1\","
        stream <<< "                .target(name: \"dep2\"),"
        stream <<< "                .product(name: \"dep3\", package: \"Pkg\"),"
        stream <<< "                .product(name: \"dep4\"),"
        stream <<< "            ]),"
        stream <<< "        .testTarget("
        stream <<< "            name: \"bar\","
        stream <<< "            dependencies: ["
        stream <<< "                \"foo\","
        stream <<< "            ]),"
        stream <<< "    ]"
        stream <<< ")"

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
        stream <<< "import PackageDescription" <<< "\n"
        stream <<< "let package = Package(" <<< "\n"
        stream <<< "   name: \"Foo\"," <<< "\n"
        stream <<< "   swiftLanguageVersions: [3, 4]" <<< "\n"
        stream <<< ")" <<< "\n"
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.package.swiftLanguageVersions ?? [], [3, 4])
        }

        stream = BufferedOutputByteStream()
        stream <<< "import PackageDescription" <<< "\n"
        stream <<< "let package = Package(" <<< "\n"
        stream <<< "   name: \"Foo\"," <<< "\n"
        stream <<< "   swiftLanguageVersions: []" <<< "\n"
        stream <<< ")" <<< "\n"
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.package.swiftLanguageVersions!, [])
        }

        stream = BufferedOutputByteStream()
        stream <<< "import PackageDescription" <<< "\n"
        stream <<< "let package = Package(" <<< "\n"
        stream <<< "   name: \"Foo\")" <<< "\n"
        loadManifest(stream.bytes) { manifest in
            XCTAssert(manifest.package.swiftLanguageVersions == nil)
        }
    }

    func testPackageDependencies() throws {
        let stream = BufferedOutputByteStream()
        stream <<< "import PackageDescription" <<< "\n"
        stream <<< "let package = Package(" <<< "\n"
        stream <<< "   name: \"Foo\"," <<< "\n"
        stream <<< "   dependencies: [" <<< "\n"
        stream <<< "       .package(url: \"/foo1\", from: \"1.0.0\")," <<< "\n"
        stream <<< "       .package(url: \"/foo2\", .upToNextMajor(from: \"1.0.0\"))," <<< "\n"
        stream <<< "       .package(url: \"/foo3\", .upToNextMinor(from: \"1.0.0\"))," <<< "\n"
        stream <<< "       .package(url: \"/foo4\", .exact(\"1.0.0\"))," <<< "\n"
        stream <<< "       .package(url: \"/foo5\", .branch(\"master\"))," <<< "\n"
        stream <<< "       .package(url: \"/foo6\", .revision(\"58e9de4e7b79e67c72a46e164158e3542e570ab6\"))," <<< "\n"
        stream <<< "   ]" <<< "\n"
        stream <<< ")" <<< "\n"
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
        stream <<< "import PackageDescription" <<< "\n"
        stream <<< "let package = Package(" <<< "\n"
        stream <<< "   name: \"Foo\"," <<< "\n"
        stream <<< "   products: [" <<< "\n"
        stream <<< "       .executable(name: \"tool\", targets: [\"tool\"])," <<< "\n"
        stream <<< "       .library(name: \"Foo\", targets: [\"Foo\"])," <<< "\n"
        stream <<< "       .library(name: \"FooDy\", type: .dynamic, targets: [\"Foo\"])," <<< "\n"
        stream <<< "   ]" <<< "\n"
        stream <<< ")" <<< "\n"
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
        stream <<< "import PackageDescription" <<< "\n"
        stream <<< "let package = Package(" <<< "\n"
        stream <<< "   name: \"Copenssl\"," <<< "\n"
        stream <<< "   pkgConfig: \"openssl\"," <<< "\n"
        stream <<< "   providers: [" <<< "\n"
        stream <<< "       .brew([\"openssl\"])," <<< "\n"
        stream <<< "       .apt([\"openssl\", \"libssl-dev\"])," <<< "\n"
        stream <<< "   ]" <<< "\n"
        stream <<< ")" <<< "\n"
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
        stream <<< "import PackageDescription" <<< "\n"
        stream <<< "let package = Package(" <<< "\n"
        stream <<< "   name: \"libyaml\"," <<< "\n"
        stream <<< "   targets: [" <<< "\n"
        stream <<< "       .target(" <<< "\n"
        stream <<< "           name: \"Foo\"," <<< "\n"
        stream <<< "           publicHeadersPath: \"inc\")," <<< "\n"
        stream <<< "       .target(" <<< "\n"
        stream <<< "       name: \"Bar\")," <<< "\n"
        stream <<< "   ]" <<< "\n"
        stream <<< ")" <<< "\n"
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
        stream <<< "import PackageDescription" <<< "\n"
        stream <<< "let package = Package(" <<< "\n"
        stream <<< "   name: \"libyaml\"," <<< "\n"
        stream <<< "   targets: [" <<< "\n"
        stream <<< "       .target(" <<< "\n"
        stream <<< "           name: \"Foo\"," <<< "\n"
        stream <<< "           path: \"foo/z\"," <<< "\n"
        stream <<< "           exclude: [\"bar\"]," <<< "\n"
        stream <<< "           sources: [\"bar.swift\"]," <<< "\n"
        stream <<< "           publicHeadersPath: \"inc\")," <<< "\n"
        stream <<< "       .target(" <<< "\n"
        stream <<< "       name: \"Bar\")," <<< "\n"
        stream <<< "   ]" <<< "\n"
        stream <<< ")" <<< "\n"
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
    ]
}
