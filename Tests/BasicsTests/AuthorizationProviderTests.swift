/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

import Basics
import TSCBasic
import TSCTestSupport

final class AuthorizationProviderTests: XCTestCase {
    func testBasicAPIs() {
        struct TestProvider: AuthorizationProvider {
            private var map = [URL: (user: String, password: String)]()
            
            mutating func addOrUpdate(for url: Foundation.URL, user: String, password: String, callback: @escaping (Result<Void, Error>) -> Void) {
                self.map[url] = (user, password)
                callback(.success(()))
            }

            func authentication(for url: URL) -> (user: String, password: String)? {
                return self.map[url]
            }
        }

        var provider = TestProvider()
        self.run(for: &provider)
    }
    
    func testNetrc() throws {
        try testWithTemporaryDirectory { tmpPath in
            let netrcPath = tmpPath.appending(component: ".netrc")
            
            var provider = try NetrcAuthorizationProvider(path: netrcPath, fileSystem: localFileSystem)
            self.run(for: &provider)
        }
    }
    
    func testKeychain() throws {
        #if os(macOS) && ENABLE_KEYCHAIN_TEST
        #else
        try XCTSkipIf(true)
        #endif
        
        var provider = KeychainAuthorizationProvider()
        self.run(for: &provider)
    }
    
    private func run<Provider>(for provider: inout Provider) where Provider: AuthorizationProvider {
        let user = UUID().uuidString
        
        let url = URL(string: "http://\(UUID().uuidString)")!
        let password = UUID().uuidString
        
        let otherURL = URL(string: "https://\(UUID().uuidString)")!
        let otherPassword = UUID().uuidString
        
        // Add
        XCTAssertNoThrow(try tsc_await { callback in provider.addOrUpdate(for: url, user: user, password: password, callback: callback) })
        XCTAssertNoThrow(try tsc_await { callback in provider.addOrUpdate(for: otherURL, user: user, password: otherPassword, callback: callback) })

        let auth = provider.authentication(for: url)
        XCTAssertEqual(auth?.user, user)
        XCTAssertEqual(auth?.password, password)
        XCTAssertEqual(provider.httpAuthorizationHeader(for: url), "Basic " + "\(user):\(password)".data(using: .utf8)!.base64EncodedString())
        
        // Update
        let newPassword = UUID().uuidString
        XCTAssertNoThrow(try tsc_await { callback in provider.addOrUpdate(for: url, user: user, password: newPassword, callback: callback) })
        
        let updatedAuth = provider.authentication(for: url)
        XCTAssertEqual(updatedAuth?.user, user)
        XCTAssertEqual(updatedAuth?.password, newPassword)
        XCTAssertEqual(provider.httpAuthorizationHeader(for: url), "Basic " + "\(user):\(newPassword)".data(using: .utf8)!.base64EncodedString())
        
        let otherAuth = provider.authentication(for: otherURL)
        XCTAssertEqual(otherAuth?.user, user)
        XCTAssertEqual(otherAuth?.password, otherPassword)
    }
}
