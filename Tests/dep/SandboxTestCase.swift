/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import XCTest
import libc
import POSIX
import sys
@testable import dep
@testable import struct PackageDescription.Version

private func makeTempDirectory(prefix prefix: String) -> String {
    let tmpdir = getenv("TMPDIR") ?? "/tmp"

    return Path.join(tmpdir, "swift-get-tests-\(prefix).XXXXXX").withCString { template in
        let mutable = UnsafeMutablePointer<Int8>(template)
        let dir = libc.mkdtemp(mutable)
        return String.fromCString(dir)!
    }
}

class SandboxTestCase: XCTestCase {

    func createSandbox(forPackage package: MockPackage? = nil, body: (String, () throws -> Int) -> Void) {
        let sandboxPath: String
        if let package = package {
            sandboxPath = package.path
        } else {
            sandboxPath = makeTempDirectory(prefix: "MockSandbox")
        }

        defer {
            _ = try? rmtree(sandboxPath)
        }
        body(sandboxPath, {
            do {
                let toolPath = Path.join(__FILE__, "../../../.build/debug/swift-build").normpath
                let env = ["SWIFT_BUILD_TOOL": getenv("SWIFT_BUILD_TOOL")!]
                try popen([toolPath, "--chdir", sandboxPath], environment: env)
                return 0
            } catch POSIX.Error.ExitStatus(let code, _) {
                return Int(code)
            }
        })
    }


    func testSwiftGet(fixtureName fixtureName: String, body: (prefix: String, baseURL: String, (String) throws -> Int) -> Void) {
        let path = makeTempDirectory(prefix: "MockGithub")
        do {
            let tmpdir = makeTempDirectory(prefix: fixtureName)
            defer {
                _ = try? rmtree(tmpdir)
            }
            let dstdir = try mkdir(tmpdir, "remotes")
            let version = Version(1,2,3)

            for d in walk(__FILE__, "../Fixtures", fixtureName, recursively: false) {
                guard d.isDirectory else { continue }
                let dstdir = Path.join(dstdir, d.basename).normpath
                try system("cp", "-R", d, dstdir)
                try popen([Git.tool, "-C", dstdir, "init"])
                try popen([Git.tool, "-C", dstdir, "add", "."])
                try popen([Git.tool, "-C", dstdir, "commit", "-m", "msg"])
                try popen([Git.tool, "-C", dstdir, "tag", "\(version)"])
            }

            let sandboxdir = try mkdir(tmpdir, "sandbox")

            body(prefix: sandboxdir, baseURL: dstdir, { getURL in
                do {
                    let toolPath = Path.join(__FILE__, "../../../.build/debug/swift-get").normpath
                    let env = ["SWIFT_BUILD_TOOL": getenv("SWIFT_BUILD_TOOL")!]
                    try POSIX.chdir(sandboxdir)  //TODO provide --chdir for swift-get
                    try popen([toolPath, getURL], environment: env)
                    try POSIX.chdir("/") //TODO same as above TODO
                    return 0
                } catch POSIX.Error.ExitStatus(let code, _) {
                    return Int(code)
                }
            })
        } catch {
            fatalError("testSwiftGet error: \(error)")
        }
    }
}

/**
 Creates a local package from a fixture.
 
  1. Add a new fixture to src/dep/tests/Fixtures
  2. Add some swift sources and a Package.swift
  3. In a SandboxTestCase use sandbox.get() to install the package
  4. Perform any other tests, often it is enough to verify the install

 If your fixture requires dependencies, specify them in the Package.swift
 using relative URLs to other fixtures.
*/
class MockPackage {
    let path: String

    init(fixtureName: String, version: Version) {
        do {
            path = makeTempDirectory(prefix: fixtureName)

            let fixtureDirectory = Path.join(__FILE__, "../Fixtures", fixtureName).normpath
            try rmtree(path)
            try system("cp", "-R", fixtureDirectory, path)

            // setup git repo
            try popen([Git.tool, "-C", path, "init"])
            try popen([Git.tool, "-C", path, "add", "."])
            try popen([Git.tool, "-C", path, "commit", "-m", "msg"])
            try popen([Git.tool, "-C", path, "tag", "\(version)"])
        } catch {
            fatalError("MockPackage init error: \(error)")
        }
    }

    deinit {
        _ = try? rmtree(path)
    }
}

class TestToolboxTestCase: SandboxTestCase {
    func testTestCaseClass() {
        createSandbox { sandboxPath, _ in
            XCTAssertTrue(sandboxPath.isDirectory)
        }
    }

    func testMockPackage() {
        let version = Version(1,0,0)
        let mock = MockPackage(fixtureName: "1_self_diagnostic", version: version)

        createSandbox(forPackage: mock) { sandbox, executeSwiftBuild in
            XCTAssertTrue(Path.join(mock.path, ".git").isDirectory)
            XCTAssertTrue(Path.join(mock.path, Manifest.filename).isFile)

            // fails because no sources is a failure
            XCTAssertNotEqual(try! executeSwiftBuild(), 0)
        }
    }

    func testMockGet() {
        let version = Version(1,0,0)
        let mock = MockPackage(fixtureName: "1_self_diagnostic", version: version)

        createSandbox { sandboxPath, _ in
            try! POSIX.chdir(sandboxPath)
            _ = try! get([(mock.path, version...version)], prefix: sandboxPath)
            XCTAssertTrue(Path.join(sandboxPath, "\(mock.path.basename)-\(version)").isDirectory)
        }
    }
}
