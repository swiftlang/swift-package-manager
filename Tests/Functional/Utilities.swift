/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import POSIX
import sys
import XCTest

import func POSIX.system
import func POSIX.popen


func fixture(name fixtureName: String, tag: String = "1.2.3", file: StaticString = __FILE__, line: UInt = __LINE__, @noescape body: (String) throws -> Void) {

    func gsub(input: String) -> String {
        return input.characters.split("/").map(String.init).joinWithSeparator("_")
    }

    do {
        try POSIX.mkdtemp(gsub(fixtureName)) { prefix in
            defer { _ = try? rmtree(prefix) }

            let rootd = Path.join(__FILE__, "../../../Fixtures", fixtureName).normpath

            guard rootd.isDirectory else {
                XCTFail("No such fixture: \(rootd)", file: file, line: line)
                return
            }

            if Path.join(rootd, "Package.swift").isFile {
                let dstdir = Path.join(prefix, rootd.basename).normpath
                try system("cp", "-R", rootd, dstdir)
                try body(dstdir)
            } else {
                for d in walk(rootd, recursively: false) {
                    guard d.isDirectory else { continue }
                    let dstdir = Path.join(prefix, d.basename).normpath
                    try system("cp", "-R", d, dstdir)
                    try popen(["git", "-C", dstdir, "init"])
                    try popen(["git", "-C", dstdir, "config", "user.email", "example@example.com"])
                    try popen(["git", "-C", dstdir, "config", "user.name", "Example Example"])
                    try popen(["git", "-C", dstdir, "add", "."])
                    try popen(["git", "-C", dstdir, "commit", "-m", "msg"])
                    try popen(["git", "-C", dstdir, "tag", tag])
                }
                try body(prefix)
            }
        }
    } catch {
        XCTFail(safeStringify(error), file: file, line: line)
    }
}

func executeSwiftBuild(chdir: String) throws -> String {
    let toolPath = Resources.findExecutable("swift-build")
    var env = [String:String]()
    env["SWIFT_BUILD_TOOL"] = getenv("SWIFT_BUILD_TOOL")
    return try popen([toolPath, "--chdir", chdir], redirectStandardError: true, printOutput: false, environment: env)
}

func mktmpdir(file: StaticString = __FILE__, line: UInt = __LINE__, @noescape body: (String) throws -> Void) {
    do {
        try POSIX.mkdtemp("spm-tests") { dir in
            defer { _ = try? rmtree(dir) }
            try body(dir)
        }
    } catch {
        XCTFail(safeStringify(error), file: file, line: line)
    }
}

func XCTAssertBuilds(paths: String..., file: StaticString = __FILE__, line: UInt = __LINE__) {
    let prefix = Path.join(paths)
    do {
        try executeSwiftBuild(prefix)
    } catch {
        XCTFail("`swift build' failed:\n\n\(safeStringify(error))\n", file: file, line: line)
    }
}

func XCTAssertBuildFails(paths: String..., file: StaticString = __FILE__, line: UInt = __LINE__) {
    let prefix = Path.join(paths)
    if (try? executeSwiftBuild(prefix)) != nil {
        XCTFail("`swift build' succeeded but should have failed", file: file, line: line)
    }
}

func XCTAssertFileExists(paths: String..., file: StaticString = __FILE__, line: UInt = __LINE__) {
    let path = Path.join(paths)
    if !path.isFile {
        XCTFail("Expected file doesn’t exist: \(path)", file: file, line: line)
    }
}

func XCTAssertDirectoryExists(paths: String..., file: StaticString = __FILE__, line: UInt = __LINE__) {
    let path = Path.join(paths)
    if !path.isDirectory {
        XCTFail("Expected directory doesn’t exist: \(path)", file: file, line: line)
    }
}

func XCTAssertNoSuchPath(paths: String..., file: StaticString = __FILE__, line: UInt = __LINE__) {
    let path = Path.join(paths)
    if path.exists {
        XCTFail("path exists by should not: \(path)", file: file, line: line)
    }
}

func system(args: String...) throws {
    try popen(args, redirectStandardError: true)
}

func safeStringify(error: ErrorType) -> String {
    // work around for a miscompile when converting error type to string
    // rdar://problem/23616384

    struct TempStream: OutputStreamType {
        var result: String = ""
        mutating func write(string: String) {
            result += string
        }
    }

    var stream = TempStream()
    print(error, toStream: &stream)
    return stream.result
}
