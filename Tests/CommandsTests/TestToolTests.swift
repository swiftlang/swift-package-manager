/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import SPMTestSupport
import TSCBasic
import TSCTestSupport
import Commands

final class TestToolTests: XCTestCase {
    private func execute(_ args: [String]) throws -> (stdout: String, stderr: String) {
        return try SwiftPMProduct.SwiftTest.execute(args)
    }
    
    func testUsage() throws {
        XCTAssert(try execute(["--help"]).stdout.contains("USAGE: swift test"))
    }

    func testSeeAlso() throws {
        XCTAssert(try execute(["--help"]).stdout.contains("SEE ALSO: swift build, swift run, swift package"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).stdout.contains("Swift Package Manager"))
    }

    func testNumWorkersParallelRequeriment() throws {
        // Running swift-test fixtures on linux is not yet possible.
        #if os(macOS)
        fixture(name: "Miscellaneous/EchoExecutable") { path in
            do {
                _ = try execute(["--num-workers", "1"])
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: --num-workers must be used with --parallel\n")
            }
        }
        #endif
    }
    
    func testNumWorkersValue() throws {
        #if os(macOS)
        fixture(name: "Miscellaneous/EchoExecutable") { path in
            do {
                _ = try execute(["--parallel", "--num-workers", "0"])
            } catch SwiftPMProductError.executionFailure(_, _, let stderr) {
                XCTAssertEqual(stderr, "error: '--num-workers' must be greater than zero\n")
            }
        }
        #endif
    }
  
    func testSwiftTestWithResources() throws {
        try withTemporaryDirectory { dir in
            let toolDir = dir.appending(component: "swiftTestResources")
            try localFileSystem.createDirectory(toolDir)
            try localFileSystem.writeFileContents(
              toolDir.appending(component: "Package.swift"),
              bytes: ByteString(encodingAsUTF8: """
                    // swift-tools-version:5.3
                    import PackageDescription

                    let package = Package(
                       name: "AwesomeResources",
                       targets: [
                           .target(name: "AwesomeResources", resources: [.copy("hello.txt")]),
                           .testTarget(name: "AwesomeResourcesTest", dependencies: ["AwesomeResources"], resources: [.copy("world.txt")])
                       ]
                    )
                    """)
            )
            try localFileSystem.createDirectory(toolDir.appending(component: "Sources"))
            try localFileSystem.createDirectory(toolDir.appending(components: "Sources", "AwesomeResources"))
            try localFileSystem.writeFileContents(
              toolDir.appending(components: "Sources", "AwesomeResources", "AwesomeResource.swift"),
              bytes: ByteString(encodingAsUTF8: """
                    import Foundation

                    public struct AwesomeResource {
                      public init() {}
                      public let hello = try! String(contentsOf: Bundle.module.url(forResource: "hello", withExtension: "txt")!)
                    }

                    """)
            )

            try localFileSystem.writeFileContents(
              toolDir.appending(components: "Sources", "AwesomeResources", "hello.txt"),
              bytes: ByteString(encodingAsUTF8: "hello")
            )

            try localFileSystem.createDirectory(toolDir.appending(component: "Tests"))
            try localFileSystem.createDirectory(toolDir.appending(components: "Tests", "AwesomeResourcesTest"))

            try localFileSystem.writeFileContents(
              toolDir.appending(components: "Tests", "AwesomeResourcesTest", "world.txt"),
              bytes: ByteString(encodingAsUTF8: "world")
            )

            try localFileSystem.writeFileContents(
                toolDir.appending(components: "Tests", "AwesomeResourcesTest", "MyTests.swift"),
                bytes: ByteString(encodingAsUTF8: """
                    import XCTest
                    import Foundation
                    import AwesomeResources

                    final class MyTests: XCTestCase {
                        func testFoo() {
                            XCTAssertTrue(AwesomeResource().hello == "hello")
                        }
                        func testBar() {
                            let world = try! String(contentsOf: Bundle.module.url(forResource: "world", withExtension: "txt")!)
                            XCTAssertTrue(world == "world")
                        }
                    }
                    """))
          
            XCTAssert(try execute(["--package-path", "\(toolDir)", "--filter", "MyTests.*"]).stderr.contains("Executed 2 tests, with 0 failures"))

        }
    }
}
