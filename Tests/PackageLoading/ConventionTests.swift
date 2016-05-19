/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import PackageDescription
import PackageModel
import Utility

@testable import PackageLoading

/// Tests for the handling of source layout conventions.
class ConventionTests: XCTestCase {
    /// Parse the given test files according to the conventions, and check the result.
    private func test<T: Module>(files: [String], file: StaticString = #file, line: UInt = #line, body: (T) throws -> ()) {
        do {
            try fixture(files: files) { (package, modules) in 
                XCTAssertEqual(modules.count, 1)
                guard let module = modules.first as? T else { XCTFail(file: #file, line: line); return }
                XCTAssertEqual(module.name, package.name)
                do {
                    try body(module)
                } catch {
                    XCTFail("\(error)", file: file, line: line)
                }
            }
        } catch {
            XCTFail("\(error)", file: file, line: line)
        }
    }
    
    func testDotFilesAreIgnored() throws {
        do {
            try fixture(files: [".Bar.swift", "Foo.swift"]) { (package, modules) in
                XCTAssertEqual(modules.count, 1)
                guard let swiftModule = modules.first as? SwiftModule else { return XCTFail() }
                XCTAssertEqual(swiftModule.sources.paths.count, 1)
                XCTAssertEqual(swiftModule.sources.paths.first?.basename, "Foo.swift")
                XCTAssertEqual(swiftModule.name, package.name)
            }
        } catch {
            XCTFail("\(error)")
        }
    }

    func testResolvesSingleSwiftModule() throws {
        let files = ["Foo.swift"]
        test(files: files) { (module: SwiftModule) in 
            XCTAssertEqual(module.sources.paths.count, files.count)
            XCTAssertEqual(Set(module.sources.relativePaths), Set(files))
        }
    }

    func testResolvesSystemModulePackage() throws {
        test(files: ["module.modulemap"]) { module in }
    }

    func testResolvesSingleClangModule() throws {
        test(files: ["Foo.c", "Foo.h"]) { module in }
    }
}

extension ConventionTests {
    static var allTests : [(String, (ConventionTests) -> () throws -> Void)] {
        return [
            ("testDotFilesAreIgnored", testDotFilesAreIgnored),
            ("testResolvesSingleSwiftModule", testResolvesSingleSwiftModule),
            ("testResolvesSystemModulePackage", testResolvesSystemModulePackage),
            ("testResolvesSingleClangModule", testResolvesSingleClangModule),
        ]
    }
}

/// Create a test fixture with empty files at the given paths.
private func fixture(files: [String], body: @noescape (String) throws -> ()) {
    mktmpdir { prefix in
        try Utility.makeDirectories(prefix)
        for file in files {
            try system("touch", Path.join(prefix, file))
        }
        try body(prefix)
    }
}

/// Check the behavior of a test project with the given file paths.
private func fixture(files: [String], file: StaticString = #file, line: UInt = #line, body: @noescape (PackageModel.Package, [Module]) throws -> ()) throws {
    fixture(files: files) { (prefix: String) in
        let manifest = Manifest(path: Path.join(prefix, "Package.swift"), package: Package(name: "name"), products: [])
        let package = Package(manifest: manifest, url: prefix)
        let modules = try package.modules()
        try body(package, modules)
    }
}
