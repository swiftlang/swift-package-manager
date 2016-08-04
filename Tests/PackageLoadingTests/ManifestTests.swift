/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TestSupport
import Basic
import PackageDescription
import PackageModel

import func POSIX.getenv
import func POSIX.popen

@testable import PackageLoading
@testable import Utility

#if os(macOS)
private func bundleRoot() -> AbsolutePath {
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        return AbsolutePath(bundle.bundlePath).parentDirectory
    }
    fatalError()
}
#endif

private struct Resources: ManifestResourceProvider {
#if os(macOS)
  #if Xcode
    let swiftCompilerPath: AbsolutePath = {
        let swiftc: AbsolutePath
        if let base = getenv("XCODE_DEFAULT_TOOLCHAIN_OVERRIDE")?.chuzzle() {
            swiftc = AbsolutePath(base).appending(components: "usr", "bin", "swiftc")
        } else if let override = getenv("SWIFT_EXEC")?.chuzzle() {
            swiftc = AbsolutePath(override)
        } else {
            swiftc = try! AbsolutePath(popen(["xcrun", "--find", "swiftc"]).chuzzle() ?? "BADPATH")
        }
        precondition(swiftc != AbsolutePath("/usr/bin/swiftc"))
        return swiftc
    }()
  #else
    let swiftCompilerPath = bundleRoot().appending(component: "swiftc")
  #endif
    let libraryPath = bundleRoot()
#else
    let libraryPath = AbsolutePath(CommandLine.arguments.first!, relativeTo: currentWorkingDirectory).parentDirectory
    let swiftCompilerPath = AbsolutePath(CommandLine.arguments.first!, relativeTo: currentWorkingDirectory).parentDirectory.appending(component: "swiftc")
#endif
}

class ManifestTests: XCTestCase {
    private func loadManifest(_ inputName: String, line: UInt = #line, body: (Manifest) -> Void) {
        do {
            let input = AbsolutePath(#file).parentDirectory.appending(component: "Inputs").appending(component: inputName)
            body(try ManifestLoader(resources: Resources()).load(path: input, baseURL: input.parentDirectory.asString, version: nil))
        } catch {
            XCTFail("Unexpected error: \(error)", file: #file, line: line)
        }
    }

    private func loadManifest(_ contents: ByteString, line: UInt = #line, body: (Manifest) -> Void) {
        do {
            let fs = InMemoryFileSystem()
            let manifestPath = AbsolutePath.root.appending(component: Manifest.filename)
            try fs.writeFileContents(manifestPath, bytes: contents)
            body(try ManifestLoader(resources: Resources()).load(path: manifestPath, baseURL: AbsolutePath.root.asString, version: nil, fileSystem: fs))
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
        let foo = try? ManifestLoader(resources: Resources()).load(path: AbsolutePath("/non-existent-file"), baseURL: "/", version: nil)
        XCTAssertNil(foo)
    }

    func testInvalidTargetName() {
        fixture(name: "Miscellaneous/PackageWithInvalidTargets") { (prefix: AbsolutePath) in
            do {
                let manifest = try ManifestLoader(resources: Resources()).load(path: prefix.appending(component: "Package.swift"), baseURL: prefix.asString, version: nil)
                _ = try PackageBuilder(manifest: manifest, path: prefix).construct(includingTestModules: false)
            } catch ModuleError.modulesNotFound(let moduleNames) {
                XCTAssertEqual(Set(moduleNames), Set(["Bake", "Fake"]))
            } catch {
                XCTFail("Failed with error: \(error)")
            }
        }
    }

    static var allTests = [
        ("testManifestLoading", testManifestLoading),
        ("testNoManifest", testNoManifest),
        ("testInvalidTargetName", testInvalidTargetName)
    ]
}
