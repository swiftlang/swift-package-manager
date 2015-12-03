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

func fixture(name fixtureName: String, tag: String = "1.2.3", @noescape body: (String) throws -> Void) {
    do {
        try POSIX.mkdtemp(fixtureName) { prefix in
            defer { _ = try? rmtree(prefix) }

            let rootd = Path.join(__FILE__, "../Fixtures", fixtureName).normpath

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
                    try popen(["git", "-C", dstdir, "add", "."])
                    try popen(["git", "-C", dstdir, "commit", "-m", "msg"])
                    try popen(["git", "-C", dstdir, "tag", tag])
                }
                try body(prefix)
            }
        }
    } catch {
        // Work around for a miscompile when converting error type to string. rdar://problem/23616384
        struct TempStream: OutputStreamType {
            var result: String = ""
            mutating func write(string: String) {
                result += string
            }
        }
        var stream = TempStream()
        print(error, toStream: &stream)

        XCTFail("\(stream.result)")
    }
}


func executeSwiftBuild(chdir: String) throws {
    let toolPath = Resources.findExecutable("swift-build")
    var env = [String:String]()
    env["SWIFT_BUILD_TOOL"] = getenv("SWIFT_BUILD_TOOL")
    try system([toolPath, "--chdir", chdir], environment: env)
}

func mktmpdir(body: () throws -> Void) {
    do {
        try POSIX.mkdtemp("spm-tests") { dir in
            defer {
                _ = try? POSIX.chdir("/")
                _ = try? rmtree(dir)
            }
            try POSIX.chdir(dir)
            try body()
        }
    } catch {
        XCTFail("\(error)")
    }
}
