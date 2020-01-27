/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic
import TSCUtility

#if os(macOS)
import class Foundation.Bundle
#endif

@_exported import TSCTestSupport

public func XCTAssertBuilds(
    _ path: AbsolutePath,
    configurations: Set<Configuration> = [.Debug, .Release],
    extraArgs: [String] = [],
    file: StaticString = #file,
    line: UInt = #line,
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: [String: String]? = nil
) {
    for conf in configurations {
        do {
            print("    Building \(conf)")
            _ = try executeSwiftBuild(
                path,
                configuration: conf,
                extraArgs: extraArgs,
                Xcc: Xcc,
                Xld: Xld,
                Xswiftc: Xswiftc,
                env: env)
        } catch {
            XCTFail("""
                `swift build -c \(conf)' failed:
                
                \(error)
                
                """, file: file, line: line)
        }
    }
}

public func XCTAssertSwiftTest(
    _ path: AbsolutePath,
    file: StaticString = #file,
    line: UInt = #line,
    env: [String: String]? = nil
) {
    do {
        _ = try SwiftPMProduct.SwiftTest.execute([], packagePath: path, env: env)
    } catch {
        XCTFail("""
            `swift test' failed:

            \(error)

            """, file: file, line: line)
    }
}

public func XCTAssertBuildFails(
    _ path: AbsolutePath,
    file: StaticString = #file,
    line: UInt = #line,
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: [String: String]? = nil
) {
    do {
        _ = try executeSwiftBuild(path, Xcc: Xcc, Xld: Xld, Xswiftc: Xswiftc)

        XCTFail("`swift build' succeeded but should have failed", file: file, line: line)

    } catch SwiftPMProductError.executionFailure(let error, _, _) {
        switch error {
        case ProcessResult.Error.nonZeroExit(let result) where result.exitStatus != .terminated(code: 0):
            break
        default:
            XCTFail("`swift build' failed in an unexpected manner")
        }
    } catch {
        XCTFail("`swift build' failed in an unexpected manner")
    }
}
