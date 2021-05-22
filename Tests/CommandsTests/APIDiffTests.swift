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
            }
        }
        #else
        throw XCTSkip("Test unsupported on current platform")
        #endif
    }

    func testCheckVendedModulesOnly() throws {
        #if os(macOS)
        guard (try? Resources.default.toolchain.getSwiftAPIDigester()) != nil else {
            throw XCTSkip("swift-api-digester not available")
        }
        fixture(name: "Miscellaneous/APIDiff/") { prefix in
            let packageRoot = prefix.appending(component: "NonAPILibraryTargets")
            try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Foo", "Foo.swift")) {
                $0 <<< "public func baz() -> String { \"hello, world!\" }"
            }
            try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Bar", "Bar.swift")) {
                $0 <<< "public class Qux<T, U> { private let x = 1 }"
            }
            try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Baz", "Baz.swift")) {
                $0 <<< "public enum Baz {case a, b, c }"
            }
            try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Qux", "Qux.swift")) {
                $0 <<< "public class Qux<T, U> { private let x = 1 }"
            }
            XCTAssertThrowsError(try execute(["experimental-api-diff", "1.2.3"], packagePath: packageRoot)) { error in
                guard case SwiftPMProductError.executionFailure(error: _, output: let output, stderr: _) = error else {
                    XCTFail("Unexpected error")
                    return
                }
                XCTAssertTrue(output.contains("1 breaking change detected in Foo"))
                XCTAssertTrue(output.contains("💔 API breakage: struct Foo has been removed"))
                XCTAssertTrue(output.contains("1 breaking change detected in Bar"))
                XCTAssertTrue(output.contains("💔 API breakage: func bar() has been removed"))
                XCTAssertTrue(output.contains("1 breaking change detected in Baz"))
                XCTAssertTrue(output.contains("💔 API breakage: enumelement Baz.b has been added as a new enum case"))

                // Qux is not part of a library product, so any API changes should be ignored
                XCTAssertFalse(output.contains("2 breaking changes detected in Qux"))
                XCTAssertFalse(output.contains("💔 API breakage: class Qux has generic signature change from <T> to <T, U>"))
                XCTAssertFalse(output.contains("💔 API breakage: var Qux.x has been removed"))
            }
        }
        #else
        throw XCTSkip("Test unsupported on current platform")
        #endif
    }

    func testFilters() throws {
        #if os(macOS)
        guard (try? Resources.default.toolchain.getSwiftAPIDigester()) != nil else {
            throw XCTSkip("swift-api-digester not available")
        }
        fixture(name: "Miscellaneous/APIDiff/") { prefix in
            let packageRoot = prefix.appending(component: "NonAPILibraryTargets")
            try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Foo", "Foo.swift")) {
                $0 <<< "public func baz() -> String { \"hello, world!\" }"
            }
            try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Bar", "Bar.swift")) {
                $0 <<< "public class Qux<T, U> { private let x = 1 }"
            }
            try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Baz", "Baz.swift")) {
                $0 <<< "public enum Baz {case a, b, c }"
            }
            try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Qux", "Qux.swift")) {
                $0 <<< "public class Qux<T, U> { private let x = 1 }"
            }
            XCTAssertThrowsError(try execute(["experimental-api-diff", "1.2.3", "--product", "One", "--target", "Bar"],
                                             packagePath: packageRoot)) { error in
                guard case SwiftPMProductError.executionFailure(error: _, output: let output, stderr: _) = error else {
                    XCTFail("Unexpected error")
                    return
                }

                XCTAssertTrue(output.contains("1 breaking change detected in Foo"))
                XCTAssertTrue(output.contains("💔 API breakage: struct Foo has been removed"))
                XCTAssertTrue(output.contains("1 breaking change detected in Bar"))
                XCTAssertTrue(output.contains("💔 API breakage: func bar() has been removed"))

                XCTAssertFalse(output.contains("1 breaking change detected in Baz"))
                XCTAssertFalse(output.contains("💔 API breakage: enumelement Baz.b has been added as a new enum case"))
                XCTAssertFalse(output.contains("2 breaking changes detected in Qux"))
                XCTAssertFalse(output.contains("💔 API breakage: class Qux has generic signature change from <T> to <T, U>"))
                XCTAssertFalse(output.contains("💔 API breakage: var Qux.x has been removed"))
            }

            // Diff a target which didn't have a baseline generated as part of the first invocation
            XCTAssertThrowsError(try execute(["experimental-api-diff", "1.2.3", "--target", "Baz"],
                                             packagePath: packageRoot)) { error in
                guard case SwiftPMProductError.executionFailure(error: _, output: let output, stderr: _) = error else {
                    XCTFail("Unexpected error")
                    return
                }

                XCTAssertTrue(output.contains("1 breaking change detected in Baz"))
                XCTAssertTrue(output.contains("💔 API breakage: enumelement Baz.b has been added as a new enum case"))

                XCTAssertFalse(output.contains("1 breaking change detected in Foo"))
                XCTAssertFalse(output.contains("💔 API breakage: struct Foo has been removed"))
                XCTAssertFalse(output.contains("1 breaking change detected in Bar"))
                XCTAssertFalse(output.contains("💔 API breakage: func bar() has been removed"))
                XCTAssertFalse(output.contains("2 breaking changes detected in Qux"))
                XCTAssertFalse(output.contains("💔 API breakage: class Qux has generic signature change from <T> to <T, U>"))
                XCTAssertFalse(output.contains("💔 API breakage: var Qux.x has been removed"))
            }

            // Test diagnostics
            XCTAssertThrowsError(try execute(["experimental-api-diff", "1.2.3", "--target", "NotATarget",
                                              "--product", "NotAProduct", "--product", "Exec", "--target", "Exec"],
                                             packagePath: packageRoot)) { error in
                guard case SwiftPMProductError.executionFailure(error: _, output: _, stderr: let stderr) = error else {
                    XCTFail("Unexpected error")
                    return
                }

                XCTAssertTrue(stderr.contains("error: no such product 'NotAProduct'"))
                XCTAssertTrue(stderr.contains("error: no such target 'NotATarget'"))
                XCTAssertTrue(stderr.contains("'Exec' is not a library product"))
                XCTAssertTrue(stderr.contains("'Exec' is not a library target"))
            }
        }
        #else
        throw XCTSkip("Test unsupported on current platform")
        #endif
    }

    func testAPIDiffOfModuleWithCDependency() throws {
        #if os(macOS)
        guard (try? Resources.default.toolchain.getSwiftAPIDigester()) != nil else {
            throw XCTSkip("swift-api-digester not available")
        }
        fixture(name: "Miscellaneous/APIDiff/") { prefix in
            let packageRoot = prefix.appending(component: "CTargetDep")
            // Overwrite the existing decl.
            try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Bar", "Bar.swift")) {
                $0 <<< """
                import Foo

                public func bar() -> String {
                    foo()
                    return "hello, world!"
                }
                """
            }
            XCTAssertThrowsError(try execute(["experimental-api-diff", "1.2.3"], packagePath: packageRoot)) { error in
                guard case SwiftPMProductError.executionFailure(error: _, output: let output, stderr: _) = error else {
                    XCTFail("Unexpected error")
                    return
                }
                XCTAssertTrue(output.contains("1 breaking change detected in Bar"))
                XCTAssertTrue(output.contains("💔 API breakage: func bar() has return type change from Swift.Int to Swift.String"))
            }

            // Report an error if we explicitly ask to diff a C-family target
            XCTAssertThrowsError(try execute(["experimental-api-diff", "1.2.3", "--target", "Foo"], packagePath: packageRoot)) { error in
                guard case SwiftPMProductError.executionFailure(error: _, output: _, stderr: let stderr) = error else {
                    XCTFail("Unexpected error")
                    return
                }

                XCTAssertTrue(stderr.contains("error: 'Foo' is not a Swift language target"))
            }
        }
        #else
        throw XCTSkip("Test unsupported on current platform")
        #endif
    }

    func testNoBreakingChanges() throws {
        #if os(macOS)
        guard (try? Resources.default.toolchain.getSwiftAPIDigester()) != nil else {
            throw XCTSkip("swift-api-digester not available")
        }
        fixture(name: "Miscellaneous/APIDiff/") { prefix in
            let packageRoot = prefix.appending(component: "Bar")
            // Introduce an API-compatible change
            try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Baz", "Baz.swift")) {
                $0 <<< "public func bar() -> Int { 100 }"
            }
            let (output, _) = try execute(["experimental-api-diff", "1.2.3"], packagePath: packageRoot)
            XCTAssertTrue(output.contains("No breaking changes detected in Baz"))
            XCTAssertTrue(output.contains("No breaking changes detected in Qux"))
        }
        #else
        throw XCTSkip("Test unsupported on current platform")
        #endif
    }

    func testAPIDiffAfterAddingNewTarget() throws {
        #if os(macOS)
        guard (try? Resources.default.toolchain.getSwiftAPIDigester()) != nil else {
            throw XCTSkip("swift-api-digester not available")
        }
        fixture(name: "Miscellaneous/APIDiff/") { prefix in
            let packageRoot = prefix.appending(component: "Bar")
            try localFileSystem.createDirectory(packageRoot.appending(components: "Sources", "Foo"))
            try localFileSystem.writeFileContents(packageRoot.appending(components: "Sources", "Foo", "Foo.swift")) {
                $0 <<< "public let foo = \"All new module!\""
            }
            try localFileSystem.writeFileContents(packageRoot.appending(component: "Package.swift")) {
                $0 <<< """
                // swift-tools-version:4.2
                import PackageDescription

                let package = Package(
                    name: "Bar",
                    products: [
                        .library(name: "Baz", targets: ["Baz"]),
                        .library(name: "Qux", targets: ["Qux", "Foo"]),
                    ],
                    targets: [
                        .target(name: "Baz"),
                        .target(name: "Qux"),
                        .target(name: "Foo")
                    ]
                )
                """
            }
            let (output, _) = try execute(["experimental-api-diff", "1.2.3"], packagePath: packageRoot)
            XCTAssertTrue(output.contains("No breaking changes detected in Baz"))
            XCTAssertTrue(output.contains("No breaking changes detected in Qux"))
            XCTAssertTrue(output.contains("Skipping Foo because it does not exist in the baseline"))
        }
        #else
        throw XCTSkip("Test unsupported on current platform")
        #endif
    }

    func testBadTreeish() throws {
        #if os(macOS)
        guard (try? Resources.default.toolchain.getSwiftAPIDigester()) != nil else {
            throw XCTSkip("swift-api-digester not available")
        }
        fixture(name: "Miscellaneous/APIDiff/") { prefix in
            let packageRoot = prefix.appending(component: "Foo")
            XCTAssertThrowsError(try execute(["experimental-api-diff", "7.8.9"], packagePath: packageRoot)) { error in
                guard case SwiftPMProductError.executionFailure(error: _, output: _, stderr: let stderr) = error else {
                    XCTFail("Unexpected error")
                    return
                }
                XCTAssertTrue(stderr.contains("error: Couldn’t check out revision ‘7.8.9’"))
            }
        }
        #else
        throw XCTSkip("Test unsupported on current platform")
        #endif
    }
}
