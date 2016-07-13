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

@testable import PackageLoading
@testable import Utility

#if os(OSX)
private func bundleRoot() -> AbsolutePath {
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        return AbsolutePath(bundle.bundlePath).parentDirectory
    }
    fatalError()
}
#endif

class ManifestTests: XCTestCase {

#if os(OSX)
  #if Xcode
    let swiftc: AbsolutePath = {
        let swiftc: AbsolutePath
        if let base = getenv("XCODE_DEFAULT_TOOLCHAIN_OVERRIDE")?.chuzzle() {
            swiftc = AbsolutePath(base).appending("usr/bin/swiftc")
        } else {
            swiftc = try! AbsolutePath(popen(["xcrun", "--find", "swiftc"]).chuzzle() ?? "BADPATH")
        }
        precondition(swiftc != "/usr/bin/swiftc")
        return swiftc
    }()
  #else
    let swiftc = bundleRoot().appending("swiftc")
  #endif
    let libdir = bundleRoot()
#else
    let libdir = AbsolutePath(Process.arguments.first!.parentDirectory.abspath)
    let swiftc = AbsolutePath(Process.arguments.first!.abspath).appending("../swiftc")
#endif

    private func loadManifest(_ inputName: RelativePath, line: UInt = #line, body: (Manifest) -> Void) {
        do {
            let input = AbsolutePath(#file).appending("../Inputs").appending(inputName)
            body(try Manifest(path: input, baseURL: input.parentDirectory.asString, swiftc: swiftc.asString, libdir: libdir.asString, version: nil))
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
    }

    func testNoManifest() {
        let foo = try? Manifest(path: "/non-existent-file", baseURL: "/", swiftc: swiftc.asString, libdir: libdir.asString, version: nil)
        XCTAssertNil(foo)
    }

    func testInvalidTargetName() {
        fixture(name: "Miscellaneous/PackageWithInvalidTargets") { (prefix: AbsolutePath) in
            do {
                let manifest = try Manifest(path: prefix.appending("Package.swift"), baseURL: prefix.asString, swiftc: swiftc.asString, libdir: libdir.asString, version: nil)
                let package = Package(manifest: manifest)

                let _ = try package.modules()

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
