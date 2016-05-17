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

extension PrimitiveResolutionTests {
    static var allTests : [(String, (PrimitiveResolutionTests) -> () throws -> Void)] {
        return [
           ("testResolvesSingleSwiftModule", testResolvesSingleSwiftModule),
           ("testResolvesSystemModulePackage", testResolvesSystemModulePackage),
           ("testResolvesSingleClangModule", testResolvesSingleClangModule),
        ]
    }
}


//MARK: infrastructure

private extension PrimitiveResolutionTests {
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
}
