/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func XCTest.XCTFail

import Basic
import POSIX
import Utility

#if os(macOS)
import class Foundation.Bundle
#endif

public func XCTAssertBuilds(_ path: AbsolutePath, configurations: Set<Configuration> = [.Debug, .Release], file: StaticString = #file, line: UInt = #line, Xcc: [String] = [], Xld: [String] = [], Xswiftc: [String] = [], env: [String: String] = [:]) {
    for conf in configurations {
        do {
            print("    Building \(conf)")
            _ = try executeSwiftBuild(path, configuration: conf, printIfError: true, Xcc: Xcc, Xld: Xld, Xswiftc: Xswiftc, env: env)
        } catch {
            XCTFail("`swift build -c \(conf)' failed:\n\n\(error)\n", file: file, line: line)
        }
    }
}

public func XCTAssertSwiftTest(_ path: AbsolutePath, file: StaticString = #file, line: UInt = #line, env: [String: String] = [:]) {
    do {
        _ = try SwiftPMProduct.SwiftTest.execute([], chdir: path, env: env, printIfError: true)
    } catch {
        XCTFail("`swift test' failed:\n\n\(error)\n", file: file, line: line)
    }
}

public func XCTAssertBuildFails(_ path: AbsolutePath, file: StaticString = #file, line: UInt = #line, Xcc: [String] = [], Xld: [String] = [], Xswiftc: [String] = [], env: [String: String] = [:]) {
    do {
        _ = try executeSwiftBuild(path, Xcc: Xcc, Xld: Xld, Xswiftc: Xswiftc)

        XCTFail("`swift build' succeeded but should have failed", file: file, line: line)

    } catch POSIX.Error.exitStatus(let status, _) where status == 1{
        // noop
    } catch {
        XCTFail("`swift build' failed in an unexpected manner")
    }
}

public func XCTAssertFileExists(_ path: AbsolutePath, file: StaticString = #file, line: UInt = #line) {
    if !isFile(path) {
        XCTFail("Expected file doesn’t exist: \(path.asString)", file: file, line: line)
    }
}

public func XCTAssertDirectoryExists(_ path: AbsolutePath, file: StaticString = #file, line: UInt = #line) {
    if !isDirectory(path) {
        XCTFail("Expected directory doesn’t exist: \(path.asString)", file: file, line: line)
    }
}

public func XCTAssertNoSuchPath(_ path: AbsolutePath, file: StaticString = #file, line: UInt = #line) {
    if exists(path) {
        XCTFail("path exists but should not: \(path.asString)", file: file, line: line)
    }
}
