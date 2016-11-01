/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TestSupport
import Basic
@testable import Commands

final class BuildToolTests: XCTestCase {
    private func execute(_ args: [String], chdir: AbsolutePath? = nil) throws -> String {
        return try SwiftPMProduct.SwiftBuild.execute(args, chdir: chdir, printIfError: true)
    }
    
    func testUsage() throws {
        XCTAssert(try execute(["--help"]).contains("USAGE: swift build"))
    }

    func testVersion() throws {
        XCTAssert(try execute(["--version"]).contains("Swift Package Manager"))
    }
    func testBuildAndClean() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending(component: "Bar")
            
            // Build it.
            XCTAssertBuilds(packageRoot)
            XCTAssertFileExists(packageRoot.appending(components: ".build", "debug", "Bar"))
            XCTAssert(isDirectory(packageRoot.appending(component: ".build")))

            // Clean, and check for removal of the build directory but not Packages.
            let output = try execute(["--clean"], chdir: packageRoot)
            XCTAssertTrue(output.contains("deprecated"))
            XCTAssert(!exists(packageRoot.appending(components: ".build", "debug", "Bar")))
            // We don't delete the build folder in new resolver.
            // FIXME: Eliminate this once we switch to new resolver.
            if !SwiftPMProduct.enableNewResolver {
                XCTAssert(!isDirectory(packageRoot.appending(component: ".build")))
                XCTAssert(isDirectory(packageRoot.appending(component: "Packages")))
            }

            // Clean again to ensure we get no error.
            _ = try execute(["--clean"], chdir: packageRoot)
        }
    }

    func testConcurrentBuild() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending(component: "Bar")

            var result = [String]()
            var resultLock = Lock()
            func appendResult(_ output: String) {
                resultLock.withLock {
                    result.append(output)
                }
            }

            // Run swift build concurrently on the same package when it has not fetched the dependencies yet.
            let threads = (1...2).map { _ in
                return Basic.Thread {
                    let output = try! self.execute(["--enable-new-resolver"], chdir: packageRoot)
                    appendResult(output)
                }
            }
            threads.forEach { $0.start() }
            threads.forEach { $0.join() }

            XCTAssertFileExists(packageRoot.appending(components: ".build", "debug", "Bar"))
            XCTAssert(isDirectory(packageRoot.appending(component: ".build")))
            // We should have one compilation and one incremental null build.
            XCTAssertTrue(result.sorted()[1].contains("Compile"))
            XCTAssertTrue(result.contains(""))
        }
    }


    static var allTests = [
        ("testConcurrentBuild", testConcurrentBuild),
        ("testUsage", testUsage),
        ("testVersion", testVersion),
        ("testBuildAndClean", testBuildAndClean),
    ]
}
