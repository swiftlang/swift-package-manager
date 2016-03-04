/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import ManifestParser
@testable import Utility
import func POSIX.getenv
import PackageDescription
import PackageType
import XCTest

class ManifestTests: XCTestCase {

#if os(OSX)
  #if Xcode
    let swiftc = Path.join(getenv("XCODE_DEFAULT_TOOLCHAIN_OVERRIDE")!, "usr/bin/swiftc")
  #else
    let swiftc = Toolchain.swiftc
  #endif
    let libdir = { _ -> String in
        for bundle in NSBundle.allBundles() where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundlePath.parentDirectory
        }
        fatalError()
    }()
#else
    let swiftc = Toolchain.swiftc
    let libdir = Process.arguments.first!.parentDirectory
#endif

    private func loadManifest(inputName: String, line: UInt = #line, body: (Manifest) -> Void) {
        do {
            let input = Path.join(#file, "../Inputs", inputName).normpath
            body(try Manifest(path: input, baseURL: input.parentDirectory, swiftc: swiftc, libdir: libdir))
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
        let foo = try? Manifest(path: "/non-existent-file", baseURL: "/", swiftc: swiftc, libdir: libdir)
        XCTAssertNil(foo)
    }
}
