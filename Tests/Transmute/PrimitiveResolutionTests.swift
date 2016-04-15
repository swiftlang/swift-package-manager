/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@testable import Transmute
import struct Utility.Path
import PackageDescription
import PackageType
import XCTest

class PrimitiveResolutionTests: XCTestCase {
    func testResolvesSingleSwiftModule() throws {
        let files = ["Foo.swift"]
        let module: SwiftModule = try test(files: files)
        XCTAssertEqual(module.sources.paths.count, files.count)
        XCTAssertEqual(Set(module.sources.relativePaths), Set(files))
    }

    func testResolvesSystemModulePackage() throws {
        let _: CModule = try test(files: ["module.modulemap"])
    }

    func testResolvesSingleClangModule() throws {
        let _: ClangModule = try test(files: ["Foo.c", "Foo.h"])
    }
}


//MARK: infrastructure

extension PrimitiveResolutionTests {
    private func test<T: Module>(files: [String], line: UInt = #line) throws -> T! {
        let (package, modules) = try fixture(files: files)
        XCTAssertEqual(modules.count, 1)
        guard let module = modules.first as? T else { XCTFail(file: #file, line: line); return nil }
        XCTAssertEqual(module.name, package.name)
        return module
    }
}
