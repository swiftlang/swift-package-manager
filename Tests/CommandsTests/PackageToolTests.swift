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
import Commands

final class PackageToolTests: XCTestCase {
    private func execute(_ args: [String], chdir: AbsolutePath? = nil) throws -> String {
        return try SwiftPMProduct.SwiftPackage.execute(args, chdir: chdir, printIfError: true)
    }
    
    func testUsage() throws {
        XCTAssert(try execute(["--help"]).contains("USAGE: swift package"))
    }
    
    func testVersion() throws {
        XCTAssert(try execute(["--version"]).contains("Swift Package Manager"))
    }

    func testFetch() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending(component: "Bar")
            let packagesPath = packageRoot.appending(component: "Packages")

            // Check that `fetch` works.
            _ = try execute(["fetch"], chdir: packageRoot)
            XCTAssertEqual(try localFileSystem.getDirectoryContents(packagesPath), ["Foo-1.2.3"])
        }
    }

    func testUpdate() throws {
        fixture(name: "DependencyResolution/External/Simple") { prefix in
            let packageRoot = prefix.appending(component: "Bar")
            let packagesPath = packageRoot.appending(component: "Packages")

            // Perform an initial fetch.
            _ = try execute(["fetch"], chdir: packageRoot)
            XCTAssertEqual(try localFileSystem.getDirectoryContents(packagesPath), ["Foo-1.2.3"])

            // Retag the dependency, and update.
            try tagGitRepo(prefix.appending(component: "Foo"), tag: "1.2.4")
            _ = try execute(["update"], chdir: packageRoot)
            XCTAssertEqual(try localFileSystem.getDirectoryContents(packagesPath), ["Foo-1.2.4"])
        }
    }

    func testDumpPackage() throws {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let packageRoot = prefix.appending(component: "app")
            let dumpOutput = try execute(["dump-package"], chdir: packageRoot)
            let json = try JSON(bytes: ByteString(encodingAsUTF8: dumpOutput))
            guard case let .dictionary(contents) = json else { XCTFail("unexpected result"); return }
            guard case let .string(name)? = contents["name"] else { XCTFail("unexpected result"); return }
            XCTAssertEqual(name, "Dealer")
        }
    }

    func testShowDependencies() throws {
        fixture(name: "DependencyResolution/External/Complex") { prefix in
            let packageRoot = prefix.appending(component: "app")
            let textOutput = try execute(["show-dependencies", "--format=text"], chdir: packageRoot)
            XCTAssert(textOutput.contains("FisherYates@1.2.3"))

            // FIXME: We have to fetch first otherwise the fetching output is mingled with the JSON data.
            let jsonOutput = try execute(["show-dependencies", "--format=json"], chdir: packageRoot)
            print("output = \(jsonOutput)")
            let json = try JSON(bytes: ByteString(encodingAsUTF8: jsonOutput))
            guard case let .dictionary(contents) = json else { XCTFail("unexpected result"); return }
            guard case let .string(name)? = contents["name"] else { XCTFail("unexpected result"); return }
            XCTAssertEqual(name, "Dealer")
            guard case let .string(path)? = contents["path"] else { XCTFail("unexpected result"); return }
            XCTAssertEqual(resolveSymlinks(AbsolutePath(path)), resolveSymlinks(packageRoot))
        }
    }

    func testInitEmpty() throws {
        mktmpdir { tmpPath in
            var fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            try fs.createDirectory(path)
            _ = try execute(["-C", path.asString, "init", "--type", "empty"])
            XCTAssert(fs.exists(path.appending(component: "Package.swift")))
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Sources")), [])
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Tests")), [])
        }
    }

    func testInitExecutable() throws {
        mktmpdir { tmpPath in
            var fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            try fs.createDirectory(path)
            _ = try execute(["-C", path.asString, "init", "--type", "executable"])
            XCTAssert(fs.exists(path.appending(component: "Package.swift")))
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Sources")), ["main.swift"])
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Tests")), [])
        }
    }

    func testInitLibrary() throws {
        mktmpdir { tmpPath in
            var fs = localFileSystem
            let path = tmpPath.appending(component: "Foo")
            try fs.createDirectory(path)
            _ = try execute(["-C", path.asString, "init"])
            XCTAssert(fs.exists(path.appending(component: "Package.swift")))
            XCTAssertEqual(try fs.getDirectoryContents(path.appending(component: "Sources")), ["Foo.swift"])
            XCTAssertEqual(
                try fs.getDirectoryContents(path.appending(component: "Tests")).sorted(),
                ["FooTests", "LinuxMain.swift"])
        }
    }

    static var allTests = [
        ("testUsage", testUsage),
        ("testVersion", testVersion),
        ("testFetch", testFetch),
        ("testUpdate", testUpdate),
        ("testDumpPackage", testDumpPackage),
        ("testShowDependencies", testShowDependencies),
        ("testInitEmpty", testInitEmpty),
        ("testInitExecutable", testInitExecutable),
        ("testInitLibrary", testInitLibrary),
    ]
}
