//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import PackageModel
import TSCBasic
import TSCUtility
import XCTest

class PackageModelTests: XCTestCase {
    func testProductTypeCodable() throws {
        struct Foo: Codable, Equatable {
            var type: ProductType
        }

        func checkCodable(_ type: ProductType) {
            do {
                let foo = Foo(type: type)
                let data = try JSONEncoder.makeWithDefaults().encode(foo)
                let decodedFoo = try JSONDecoder.makeWithDefaults().decode(Foo.self, from: data)
                XCTAssertEqual(foo, decodedFoo)
            } catch {
                XCTFail("\(error)")
            }
        }

        checkCodable(.library(.automatic))
        checkCodable(.library(.static))
        checkCodable(.library(.dynamic))
        checkCodable(.executable)
        checkCodable(.test)
    }
    
    func testProductFilterCodable() throws {
        // Test ProductFilter.everything
        try {
            let data = try JSONEncoder().encode(ProductFilter.everything)
            let decoded = try JSONDecoder().decode(ProductFilter.self, from: data)
            XCTAssertEqual(decoded, ProductFilter.everything)
        }()
        // Test ProductFilter.specific(), including that the order is normalized
        try {
            let data = try JSONEncoder().encode(ProductFilter.specific(["Bar", "Foo"]))
            let decoded = try JSONDecoder().decode(ProductFilter.self, from: data)
            XCTAssertEqual(decoded, ProductFilter.specific(["Foo", "Bar"]))
        }()
    }

    func testAndroidCompilerFlags() throws {
        let target = try Triple("x86_64-unknown-linux-android")
        let sdk = AbsolutePath("/some/path/to/an/SDK.sdk")
        let toolchainPath = AbsolutePath("/some/path/to/a/toolchain.xctoolchain")

        let destination = Destination(
            target: target,
            sdk: sdk,
            binDir: toolchainPath.appending(components: "usr", "bin")
        )

        XCTAssertEqual(UserToolchain.deriveSwiftCFlags(triple: target, destination: destination, environment: .process()), [
            // Needed when cross‐compiling for Android. 2020‐03‐01
            "-sdk", sdk.pathString,
        ])
    }
}
