//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest

@testable import PackageCollections

class ValidationMessageTests: XCTestCase {
    func testMessageToError() {
        let warningWithProperty = ValidationMessage.warning("warning with property", property: "foo")
        let warning = ValidationMessage.warning("warning")
        let errorWithProperty = ValidationMessage.error("error with property", property: "bar")
        let error = ValidationMessage.error("error")

        let messages = [warningWithProperty, errorWithProperty, warning, error]

        do {
            let errors = messages.errors(include: [.warning])!
            XCTAssertEqual(2, errors.count)

            guard case .property(_, let m0) = errors[0], m0 == warningWithProperty.message else {
                return XCTFail("Expected .property error")
            }
            guard case .other(let m1) = errors[1], m1 == warning.message else {
                return XCTFail("Expected .other error")
            }
        }

        do {
            let errors = messages.errors(include: [.error])!
            XCTAssertEqual(2, errors.count)

            guard case .property(_, let m0) = errors[0], m0 == errorWithProperty.message else {
                return XCTFail("Expected .property error")
            }
            guard case .other(let m1) = errors[1], m1 == error.message else {
                return XCTFail("Expected .other error")
            }
        }

        do {
            let errors = messages.errors(include: [.warning, .error])!
            XCTAssertEqual(4, errors.count)
        }
    }
}
