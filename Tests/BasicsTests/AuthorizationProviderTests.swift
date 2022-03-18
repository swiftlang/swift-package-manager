//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest

@testable import Basics
import TSCBasic
import TSCTestSupport

final class AuthorizationProviderTests: XCTestCase {
    func testBasicAPIs() {
        let url = URL(string: "http://\(UUID().uuidString)")!
        let user = UUID().uuidString
        let password = UUID().uuidString

        let provider = TestProvider(map: [url: (user: user, password: password)])
        self.assertAuthentication(provider, for: url, expected: (user, password))
    }

    func testNetrc() throws {
        try testWithTemporaryDirectory { tmpPath in
            let netrcPath = tmpPath.appending(component: ".netrc")

            var provider = try NetrcAuthorizationProvider(path: netrcPath, fileSystem: localFileSystem)

            let user = UUID().uuidString

            let url = URL(string: "http://\(UUID().uuidString)")!
            let password = UUID().uuidString

            let otherURL = URL(string: "https://\(UUID().uuidString)")!
            let otherPassword = UUID().uuidString

            // Add
            XCTAssertNoThrow(try tsc_await { callback in provider.addOrUpdate(for: url, user: user, password: password, callback: callback) })
            XCTAssertNoThrow(try tsc_await { callback in provider.addOrUpdate(for: otherURL, user: user, password: otherPassword, callback: callback) })

            self.assertAuthentication(provider, for: url, expected: (user, password))

            // Update - the new password is appended to the end of file
            let newPassword = UUID().uuidString
            XCTAssertNoThrow(try tsc_await { callback in provider.addOrUpdate(for: url, user: user, password: newPassword, callback: callback) })

            // .netrc file now contains two entries for `url`: one with `password` and the other with `newPassword`.
            // `NetrcAuthorizationProvider` returns the first entry it finds.
            self.assertAuthentication(provider, for: url, expected: (user, password))

            // Make sure the new entry is saved
            XCTAssertNotNil(provider.machines.first(where: { $0.name == url.host!.lowercased() && $0.login == user && $0.password == newPassword }))

            self.assertAuthentication(provider, for: otherURL, expected: (user, otherPassword))
        }
    }

    func testKeychain() throws {
        #if !canImport(Security) || !ENABLE_KEYCHAIN_TEST
        try XCTSkipIf(true)
        #else
        let provider = KeychainAuthorizationProvider(observabilityScope: ObservabilitySystem.NOOP)

        let user = UUID().uuidString

        let url = URL(string: "http://\(UUID().uuidString)")!
        let password = UUID().uuidString

        let otherURL = URL(string: "https://\(UUID().uuidString)")!
        let otherPassword = UUID().uuidString

        // Add
        XCTAssertNoThrow(try tsc_await { callback in provider.addOrUpdate(for: url, user: user, password: password, callback: callback) })
        XCTAssertNoThrow(try tsc_await { callback in provider.addOrUpdate(for: otherURL, user: user, password: otherPassword, callback: callback) })

        self.assertAuthentication(provider, for: url, expected: (user, password))

        // Update
        let newPassword = UUID().uuidString
        XCTAssertNoThrow(try tsc_await { callback in provider.addOrUpdate(for: url, user: user, password: newPassword, callback: callback) })

        // Existing password is updated
        self.assertAuthentication(provider, for: url, expected: (user, newPassword))

        self.assertAuthentication(provider, for: otherURL, expected: (user, otherPassword))
        #endif
    }

    func testComposite() throws {
        let url = URL(string: "http://\(UUID().uuidString)")!
        let user = UUID().uuidString
        let passwordOne = UUID().uuidString
        let passwordTwo = UUID().uuidString

        let providerOne = TestProvider(map: [url: (user: user, password: passwordOne)])
        let providerTwo = TestProvider(map: [url: (user: user, password: passwordTwo)])

        do {
            // providerOne's password is returned first
            let provider = CompositeAuthorizationProvider(providerOne, providerTwo, observabilityScope: ObservabilitySystem.NOOP)
            self.assertAuthentication(provider, for: url, expected: (user, passwordOne))
        }

        do {
            // providerTwo's password is returned first
            let provider = CompositeAuthorizationProvider(providerTwo, providerOne, observabilityScope: ObservabilitySystem.NOOP)
            self.assertAuthentication(provider, for: url, expected: (user, passwordTwo))
        }

        do {
            // Neither has password
            let unknownURL = URL(string: "http://\(UUID().uuidString)")!
            let provider = CompositeAuthorizationProvider(providerOne, providerTwo, observabilityScope: ObservabilitySystem.NOOP)
            XCTAssertNil(provider.authentication(for: unknownURL))
        }
    }

    private func assertAuthentication(_ provider: AuthorizationProvider, for url: URL, expected: (user: String, password: String)) {
        let authentication = provider.authentication(for: url)
        XCTAssertEqual(authentication?.user, expected.user)
        XCTAssertEqual(authentication?.password, expected.password)
        XCTAssertEqual(provider.httpAuthorizationHeader(for: url), "Basic " + "\(expected.user):\(expected.password)".data(using: .utf8)!.base64EncodedString())
    }
}

private struct TestProvider: AuthorizationProvider {
    let map: [URL: (user: String, password: String)]

    func authentication(for url: URL) -> (user: String, password: String)? {
        return self.map[url]
    }
}
