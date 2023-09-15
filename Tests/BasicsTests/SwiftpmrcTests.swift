//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import XCTest

class SwiftpmrcTests: XCTestCase {
    func testParse() throws {
        let content = """
        {
          "machines": [
            {
              "name": "example.com",
              "login": "anonymous",
              "password": "qwerty"
            },
            {
              "name": "example.com:8080",
              "password": "secret-token"
            }
          ],
          "version": 1
        }
        """

        let swiftpmrc = try Swiftpmrc.parse(content.data(using: .utf8)!)
        XCTAssertEqual(swiftpmrc.machines.count, 2)

        let basic = swiftpmrc.machines[0]
        XCTAssertEqual(basic.name, "example.com")
        XCTAssertEqual(basic.login, "anonymous")
        XCTAssertEqual(basic.password, "qwerty")

        let token = swiftpmrc.machines[1]
        XCTAssertEqual(token.name, "example.com:8080")
        XCTAssertNil(token.login)
        XCTAssertEqual(token.password, "secret-token")

        let authorizationBasic = swiftpmrc.authorization(for: "http://example.com/resource.zip")
        XCTAssertEqual(authorizationBasic?.login, "anonymous")
        XCTAssertEqual(authorizationBasic?.password, "qwerty")

        let authorizationToken = swiftpmrc.authorization(for: "http://example.com:8080/resource.zip")
        XCTAssertNil(authorizationToken?.login)
        XCTAssertEqual(authorizationToken?.password, "secret-token")

        XCTAssertNil(swiftpmrc.authorization(for: "http://example2.com/resource.zip"))
        XCTAssertNil(swiftpmrc.authorization(for: "http://www.example.com/resource.zip"))
    }

    func testUnsupportedVersion() throws {
        let content = """
        {
          "machines": [
            {
              "name": "example.com",
              "login": "anonymous",
              "password": "qwerty"
            }
          ],
          "version": 0
        }
        """

        XCTAssertThrowsError(
            try Swiftpmrc.parse(content.data(using: .utf8)!)
        ) { error in
            guard case SwiftpmrcError.unsupportedVersion = error else {
                return XCTFail("expected SwiftpmrcError.unsupportedVersion, got \(error)")
            }
        }
    }

    func testEmptyMachines() throws {
        let content = """
        {
          "machines": [],
          "version": 1
        }
        """

        XCTAssertThrowsError(
            try Swiftpmrc.parse(content.data(using: .utf8)!)
        ) { error in
            guard case SwiftpmrcError.machineNotFound = error else {
                return XCTFail("expected SwiftpmrcError.machineNotFound, got \(error)")
            }
        }
    }
}
