/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import PackageDescription
import sys
@testable import dep
import libc

class ManifestTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> ())] {
        return [
            ("testManifestLoading", testManifestLoading),
        ]
    }

    private func loadManifest(inputName: String) -> Manifest {
        let input = Path.join(__FILE__, "../Inputs", inputName).normpath
        do {
            return try Manifest(path: input)
        } catch let err {
            fatalError("unexpected error: \(err)")
        }
    }

    func testManifestLoading() {
        // Check a trivial manifest.
        var manifest = loadManifest("trivial-manifest")
        XCTAssertEqual(manifest.package.name, "Trivial")
        XCTAssertEqual(manifest.package.targets, [])
        XCTAssertEqual(manifest.package.dependencies, [])

        // Check a manifest with package specifications.
        manifest = loadManifest("package-deps-manifest")
        XCTAssertEqual(manifest.package.name, "PackageDeps")
        XCTAssertEqual(manifest.package.targets, [])
        XCTAssertEqual(manifest.package.dependencies, [Package.Dependency.Package(url: "https://example.com/example", majorVersion: 1)])

        // Check a manifest with targets.
        manifest = loadManifest("target-deps-manifest")
        XCTAssertEqual(manifest.package.name, "TargetDeps")
        XCTAssertEqual(manifest.package.targets, [
            Target(
                name: "sys",
                dependencies: [.Target(name: "libc")]),
            Target(
                name: "dep",
                dependencies: [.Target(name: "sys"), .Target(name: "libc")])])
    }
}
