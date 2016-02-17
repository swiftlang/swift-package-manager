/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import POSIX
import Utility
import XCTest

import func POSIX.system
import func POSIX.popen


func fixture(name fixtureName: String, tags: [String] = [], file: StaticString = #file, line: UInt = #line, @noescape body: (String) throws -> Void) {

    func gsub(input: String) -> String {
        return input.characters.split("/").map(String.init).joinWithSeparator("_")
    }

    do {
        try POSIX.mkdtemp(gsub(fixtureName)) { prefix in
            defer { _ = try? rmtree(prefix) }

            let rootd = Path.join(#file, "../../../Fixtures", fixtureName).normpath

            guard rootd.isDirectory else {
                XCTFail("No such fixture: \(rootd)", file: file, line: line)
                return
            }

            if Path.join(rootd, "Package.swift").isFile {
                let dstdir = Path.join(prefix, rootd.basename).normpath
                try system("cp", "-R", rootd, dstdir)
                try body(dstdir)
            } else {
                var versions = tags
                func popVersion() -> String {
                    if versions.isEmpty {
                        return "1.2.3"
                    } else if versions.count == 1 {
                        return versions.first!
                    } else {
                        return versions.removeFirst()
                    }
                }

                for d in walk(rootd, recursively: false).sort() {
                    guard d.isDirectory else { continue }
                    let dstdir = Path.join(prefix, d.basename).normpath
                    try system("cp", "-R", d, dstdir)
                    try popen(["git", "-C", dstdir, "init"])
                    try popen(["git", "-C", dstdir, "config", "user.email", "example@example.com"])
                    try popen(["git", "-C", dstdir, "config", "user.name", "Example Example"])
                    try popen(["git", "-C", dstdir, "add", "."])
                    try popen(["git", "-C", dstdir, "commit", "-m", "msg"])
                    try popen(["git", "-C", dstdir, "tag", popVersion()])
                }
                try body(prefix)
            }
        }
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

enum Configuration {
    case Debug
    case Release
}

func executeSwiftBuild(chdir: String, configuration: Configuration = .Debug, printIfError: Bool = false) throws -> String {
    let toolPath = Resources.findExecutable("swift-build")
    var env = [String:String]()
    env["SWIFT_BUILD_TOOL"] = getenv("SWIFT_BUILD_TOOL")
    var args = [toolPath, "--chdir", chdir]
    args.append("--configuration")
    switch configuration {
    case .Debug:
        args.append("debug")
    case .Release:
        args.append("release")
    }
    var out = ""
    do {
        try popen(args, redirectStandardError: true, environment: env) {
            out += $0
        }
        return out
    } catch {
        if printIfError {
            print(out)
        }
        throw error
    }
}

func mktmpdir(file: StaticString = #file, line: UInt = #line, @noescape body: (String) throws -> Void) {
    do {
        try POSIX.mkdtemp("spm-tests") { dir in
            defer { _ = try? rmtree(dir) }
            try body(dir)
        }
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

func XCTAssertBuilds(paths: String..., configurations: Set<Configuration> = [.Debug, .Release], file: StaticString = #file, line: UInt = #line) {
    let prefix = Path.join(paths)

    for conf in configurations {
        do {
            print("    Building \(conf)")
            try executeSwiftBuild(prefix, configuration: conf, printIfError: true)
        } catch {
            XCTFail("`swift build -c \(conf)' failed:\n\n\(error)\n", file: file, line: line)
        }
    }
}

func XCTAssertBuildFails(paths: String..., file: StaticString = #file, line: UInt = #line) {
    let prefix = Path.join(paths)
    if (try? executeSwiftBuild(prefix)) != nil {
        XCTFail("`swift build' succeeded but should have failed", file: file, line: line)
    }
}

func XCTAssertFileExists(paths: String..., file: StaticString = #file, line: UInt = #line) {
    let path = Path.join(paths)
    if !path.isFile {
        XCTFail("Expected file doesn’t exist: \(path)", file: file, line: line)
    }
}

func XCTAssertDirectoryExists(paths: String..., file: StaticString = #file, line: UInt = #line) {
    let path = Path.join(paths)
    if !path.isDirectory {
        XCTFail("Expected directory doesn’t exist: \(path)", file: file, line: line)
    }
}

func XCTAssertNoSuchPath(paths: String..., file: StaticString = #file, line: UInt = #line) {
    let path = Path.join(paths)
    if path.exists {
        XCTFail("path exists but should not: \(path)", file: file, line: line)
    }
}

func system(args: String...) throws {
    try popen(args, redirectStandardError: true)
}
