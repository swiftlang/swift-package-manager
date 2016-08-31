/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageDescription
import PackageModel

import func POSIX.getenv
import func POSIX.popen

import TestSupport

@testable import PackageLoading
@testable import Utility

class ManifestTests: XCTestCase {
    let manifestLoader = ManifestLoader(resources: Resources())

    private func loadManifest(_ inputName: String, line: UInt = #line, body: (Manifest) -> Void) {
        do {
            let input = AbsolutePath(#file).parentDirectory.appending(component: "Inputs").appending(component: inputName)
            body(try manifestLoader.loadFile(path: input, baseURL: input.parentDirectory.asString, version: nil))
        } catch {
            XCTFail("Unexpected error: \(error)", file: #file, line: line)
        }
    }

    private func loadManifest(_ contents: ByteString, baseURL: String? = nil, line: UInt = #line, body: (Manifest) -> Void) {
        do {
            let fs = InMemoryFileSystem()
            let manifestPath = AbsolutePath.root.appending(component: Manifest.filename)
            try fs.writeFileContents(manifestPath, bytes: contents)
            body(try manifestLoader.loadFile(path: manifestPath, baseURL: baseURL ?? AbsolutePath.root.asString, version: nil, fileSystem: fs))
        } catch {
            XCTFail("Unexpected error: \(error)", file: #file, line: line)
        }
    }

    func testManifestLoading() {
        // Check a trivial manifest.
        loadManifest("trivial-manifest") { manifest in
            XCTAssertEqual(manifest.package.name, "Trivial")
            XCTAssertEqual(manifest.package.targets, [])
            XCTAssertEqual(manifest.package.dependencies, [])
        }

        // Check a manifest with package specifications.
        loadManifest("package-deps-manifest") { manifest in
            XCTAssertEqual(manifest.package.name, "PackageDeps")
            XCTAssertEqual(manifest.package.targets, [])
            XCTAssertEqual(manifest.package.dependencies, [Package.Dependency.Package(url: "https://example.com/example", majorVersion: 1)])
        }

        // Check a manifest with targets.
        loadManifest("target-deps-manifest") { manifest in
            XCTAssertEqual(manifest.package.name, "TargetDeps")
            XCTAssertEqual(manifest.package.targets, [
                Target(
                    name: "sys",
                    dependencies: [.Target(name: "libc")]),
                Target(
                    name: "dep",
                    dependencies: [.Target(name: "sys"), .Target(name: "libc")])])
        }

        // Check loading a manifest from a file system.
        let trivialManifest = ByteString(encodingAsUTF8: (
                "import PackageDescription\n" +
                "let package = Package(name: \"Trivial\")"))
        loadManifest(trivialManifest) { manifest in
            XCTAssertEqual(manifest.package.name, "Trivial")
            XCTAssertEqual(manifest.package.targets, [])
            XCTAssertEqual(manifest.package.dependencies, [])
        }
    }

    func testNoManifest() {
        XCTAssertThrows(PackageModel.Package.Error.noManifest("/non-existent-file")) {
            _ = try manifestLoader.loadFile(path: AbsolutePath("/non-existent-file"), baseURL: "/", version: nil)
        }

        XCTAssertThrows(PackageModel.Package.Error.noManifest("/non-existent-file")) {
            _ = try manifestLoader.loadFile(path: AbsolutePath("/non-existent-file"), baseURL: "/", version: nil, fileSystem: InMemoryFileSystem())
        }
    }

    func testNonexistentBaseURL() {
        let trivialManifest = ByteString(encodingAsUTF8: (
                "import PackageDescription\n" +
                "let package = Package(name: \"Trivial\")"))
        loadManifest(trivialManifest, baseURL: "/non-existent-path") { manifest in
            XCTAssertEqual(manifest.package.name, "Trivial")
            XCTAssertEqual(manifest.package.targets, [])
            XCTAssertEqual(manifest.package.dependencies, [])
        }
    }

    func testInvalidTargetName() {
        fixture(name: "Miscellaneous/PackageWithInvalidTargets") { (prefix: AbsolutePath) in
            do {
                let manifest = try manifestLoader.loadFile(path: prefix.appending(component: "Package.swift"), baseURL: prefix.asString, version: nil)
                _ = try PackageBuilder(manifest: manifest, path: prefix).construct(includingTestModules: false)
            } catch ModuleError.modulesNotFound(let moduleNames) {
                XCTAssertEqual(Set(moduleNames), Set(["Bake", "Fake"]))
            } catch {
                XCTFail("Failed with error: \(error)")
            }
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
            let manifest = try manifestLoader.load(packagePath: root, baseURL: root.asString, version: nil, fileSystem: fs)
            XCTAssertEqual(manifest.name, "Trivial")
        }
    }
    
    static var allTests = [
        ("testManifestLoading", testManifestLoading),
        ("testNoManifest", testNoManifest),
        ("testNonexistentBaseURL", testNonexistentBaseURL),
        ("testInvalidTargetName", testInvalidTargetName),
        ("testVersionSpecificLoading", testVersionSpecificLoading),
    ]
}
