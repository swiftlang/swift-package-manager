/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import TSCBasic
import XCTest

final class AuthorizationProviderTests: XCTestCase {
    func testBasicAPIs() {
        struct TestProvider: AuthorizationProvider {
            let map: [URL: (user: String, password: String)]

            func authentication(for url: URL) -> (user: String, password: String)? {
                return self.map[url]
            }
        }

        let url = URL(string: "http://\(UUID().uuidString)")!
        let user = UUID().uuidString
        let password = UUID().uuidString
        let provider = TestProvider(map: [url: (user: user, password: password)])

        let auth = provider.authentication(for: url)
        XCTAssertEqual(auth?.user, user)
        XCTAssertEqual(auth?.password, password)
        XCTAssertEqual(provider.httpAuthorizationHeader(for: url), "Basic " + "\(user):\(password)".data(using: .utf8)!.base64EncodedString())
    }
}
