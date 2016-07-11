/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import PackageDescription
import PackageModel
import Utility

@testable import PackageLoading

/// Tests for the handling of source layout conventions.
class ConventionTests: XCTestCase {
    /// Parse the given test files according to the conventions, and check the result.
    private func test<T: Module>(files: [RelativePath], file: StaticString = #file, line: UInt = #line, body: (T) throws -> ()) {
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
        let files: [RelativePath] = ["Foo.swift"]
        test(files: files) { (module: SwiftModule) in 
            XCTAssertEqual(module.sources.paths.count, files.count)
            XCTAssertEqual(Set(module.sources.relativePaths.map{ RelativePath($0) }), Set(files))
        }
    }

    func testResolvesSystemModulePackage() throws {
        test(files: ["module.modulemap"]) { module in }
    }

    func testResolvesSingleClangModule() throws {
        test(files: ["Foo.c", "Foo.h"]) { module in }
    }

    static var allTests = [
        ("testDotFilesAreIgnored", testDotFilesAreIgnored),
        ("testResolvesSingleSwiftModule", testResolvesSingleSwiftModule),
        ("testResolvesSystemModulePackage", testResolvesSystemModulePackage),
        ("testResolvesSingleClangModule", testResolvesSingleClangModule),
    ]
}

/// Create a test fixture with empty files at the given paths.
private func fixture(files: [RelativePath], body: @noescape (AbsolutePath) throws -> ()) {
    mktmpdir { prefix in
        try Utility.makeDirectories(prefix.asString)
        for file in files {
            try system("touch", prefix.appending(file).asString)
        }
        try body(prefix)
    }
}

/// Check the behavior of a test project with the given file paths.
private func fixture(files: [RelativePath], file: StaticString = #file, line: UInt = #line, body: @noescape (PackageModel.Package, [Module]) throws -> ()) throws {
    fixture(files: files) { (prefix: AbsolutePath) in
        let manifest = Manifest(path: prefix.appending("Package.swift").asString, package: Package(name: "name"), products: [])
        let package = Package(manifest: manifest, url: prefix.asString)
        let modules = try package.modules()
        try body(package, modules)
    }
}
