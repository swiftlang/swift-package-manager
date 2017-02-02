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
    let manifestLoader = ManifestLoader(resources: Resources())

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
      // FIXME: Need to select right PD version for Xcode.
      #if !Xcode
        let stream = BufferedOutputByteStream()
        stream <<< "import PackageDescription\n"
        stream <<< "let package = Package("
        stream <<< "    name: \"Trivial\","
        stream <<< "    targets: ["
        stream <<< "        Target("
        stream <<< "            name: \"foo\","
        stream <<< "            dependencies: ["
        stream <<< "                \"dep1\","
        stream <<< "                .Target(name: \"dep2\"),"
        stream <<< "                .Product(name: \"dep3\", package: \"Pkg\"),"
        stream <<< "            ]),"
        stream <<< "    ]"
        stream <<< ")"

        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.name, "Trivial")
            let foo = manifest.package.targets[0]
            XCTAssertEqual(foo.name, "foo")

            let expectedDependencies: [PackageDescription4.Target.Dependency]
            expectedDependencies = [.ByName(name: "dep1"), .Target(name: "dep2"), .Product(name: "dep3", package: "Pkg")]
            XCTAssertEqual(foo.dependencies, expectedDependencies)
        }
      #endif
    }

    func testCompatibleSwiftVersions() throws {
      // FIXME: Need to select right PD version for Xcode.
      #if !Xcode
        var stream = BufferedOutputByteStream()
        stream <<< "import PackageDescription" <<< "\n"
        stream <<< "let package = Package(" <<< "\n"
        stream <<< "   name: \"Foo\"," <<< "\n"
        stream <<< "   compatibleSwiftVersions: [3, 4]" <<< "\n"
        stream <<< ")" <<< "\n"
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.package.compatibleSwiftVersions ?? [], [3, 4])
        }

        stream = BufferedOutputByteStream()
        stream <<< "import PackageDescription" <<< "\n"
        stream <<< "let package = Package(" <<< "\n"
        stream <<< "   name: \"Foo\"," <<< "\n"
        stream <<< "   compatibleSwiftVersions: []" <<< "\n"
        stream <<< ")" <<< "\n"
        loadManifest(stream.bytes) { manifest in
            XCTAssertEqual(manifest.package.compatibleSwiftVersions!, [])
        }

        stream = BufferedOutputByteStream()
        stream <<< "import PackageDescription" <<< "\n"
        stream <<< "let package = Package(" <<< "\n"
        stream <<< "   name: \"Foo\")" <<< "\n"
        loadManifest(stream.bytes) { manifest in
            XCTAssert(manifest.package.compatibleSwiftVersions == nil)
        }
      #endif
    }

    static var allTests = [
        ("testCompatibleSwiftVersions", testCompatibleSwiftVersions),
        ("testTargetDependencies", testTargetDependencies),
        ("testTrivial", testTrivial),
    ]
}
