/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Foundation
import TSCBasic
import Commands
import SPMTestSupport

final class APIDiffTests: XCTestCase {
    @discardableResult
    private func execute(
        _ args: [String],
        packagePath: AbsolutePath? = nil,
        env: [String: String]? = nil
    ) throws -> (stdout: String, stderr: String) {
        var environment = env ?? [:]
        // don't ignore local packages when caching
        environment["SWIFTPM_TESTS_PACKAGECACHE"] = "1"
        return try SwiftPMProduct.SwiftPackage.execute(args, packagePath: packagePath, env: environment)
    }

    func testSimpleAPIDiff() throws {
        #if os(macOS)
        guard (try? Resources.default.toolchain.getSwiftAPIDigester()) != nil else {
            throw XCTSkip("swift-api-digester not available")
        }
        fixture(name: "Miscellaneous/APIDiff/") { prefix in
            let packageRoot = prefix.appending(component: "Foo")
            // Overwrite the existing decl.
            try localFileSystem.writeFileContents(packageRoot.appending(component: "Foo.swift")) {
                $0 <<< "public let foo = 42"
            }
            XCTAssertThrowsError(try execute(["experimental-api-diff", "1.2.3"], packagePath: packageRoot)) { error in
                guard case SwiftPMProductError.executionFailure(error: _, output: let output, stderr: _) = error else {
                    XCTFail("Unexpected error")
                    return
                }
                XCTAssertTrue(output.contains("1 breaking change detected in Foo"))
                XCTAssertTrue(output.contains("💔 API breakage: func foo() has been removed"))
            }
        }
        #else
        throw XCTSkip("Test unsupported on current platform")
        #endif
    }

    func testMultiTargetAPIDiff() throws {
        #if os(macOS)
        guard (try? Resources.default.toolchain.getSwiftAPIDigester()) != nil else {
            throw XCTSkip("swift-api-digester not available")
        }
        fixture(name: "Miscellaneous/APIDiff/") { prefix in
            let packageRoot = prefix.appending(component: "Bar")
            try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Baz", "Baz.swift")) {
                $0 <<< "public func baz() -> String { \"hello, world!\" }"
            }
            try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Qux", "Qux.swift")) {
                $0 <<< "public class Qux<T, U> { private let x = 1 }"
            }
            XCTAssertThrowsError(try execute(["experimental-api-diff", "1.2.3"], packagePath: packageRoot)) { error in
                guard case SwiftPMProductError.executionFailure(error: _, output: let output, stderr: _) = error else {
                    XCTFail("Unexpected error")
                    return
                }
                XCTAssertTrue(output.contains("2 breaking changes detected in Qux"))
                XCTAssertTrue(output.contains("💔 API breakage: class Qux has generic signature change from <T> to <T, U>"))
                XCTAssertTrue(output.contains("💔 API breakage: var Qux.x has been removed"))
                XCTAssertTrue(output.contains("1 breaking change detected in Baz"))
                XCTAssertTrue(output.contains("💔 API breakage: func bar() has been removed"))
                print(output)
            }
        }
        #else
        throw XCTSkip("Test unsupported on current platform")
        #endif
    }
}
