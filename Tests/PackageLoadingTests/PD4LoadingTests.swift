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
            XCTAssertEqual(manifest.package.targets, [])
            XCTAssertEqual(manifest.package.dependencies, [])
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
        stream <<< "            ]),"
        stream <<< "    ]"
        stream <<< ")"

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.name, "Trivial")
            let foo = manifest.package.targets[0]
            XCTAssertEqual(foo.name, "foo")

            let expectedDependencies: [PackageDescription4.Target.Dependency]
            expectedDependencies = [.byNameItem(name: "dep1"), .target(name: "dep2"), .product(name: "dep3", package: "Pkg")]
            XCTAssertEqual(foo.dependencies, expectedDependencies)
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

    func testRevision() throws {
        let stream = BufferedOutputByteStream()
        stream <<< "import PackageDescription" <<< "\n"
        stream <<< "let package = Package(" <<< "\n"
        stream <<< "   name: \"Foo\"," <<< "\n"
        stream <<< "   dependencies: [" <<< "\n"
        stream <<< "       .package(url: \"/foo\", .branch(\"master\"))," <<< "\n"
        stream <<< "       .package(url: \"/bar\", .revision(\"58e9de4e7b79e67c72a46e164158e3542e570ab6\"))," <<< "\n"
        stream <<< "   ]" <<< "\n"
        stream <<< ")" <<< "\n"
        loadManifest(stream.bytes) { manifest in
            let deps = Dictionary(items: manifest.package.dependencies.map{ ($0.url, $0) })
            XCTAssertEqual(deps["/foo"], .package(url: "/foo", .branch("master")))
            XCTAssertEqual(deps["/bar"], .package(url: "/bar", .revision("58e9de4e7b79e67c72a46e164158e3542e570ab6")))
        }
    }

    static var allTests = [
        ("testCompatibleSwiftVersions", testCompatibleSwiftVersions),
        ("testTargetDependencies", testTargetDependencies),
        ("testTrivial", testTrivial),
        ("testRevision", testRevision),
    ]
}
