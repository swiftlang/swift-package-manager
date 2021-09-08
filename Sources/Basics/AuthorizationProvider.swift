/*
 This source file is part of the Swift.org open source project
 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation

public protocol AuthorizationProvider {
    func authentication(for url: URL) -> (user: String, password: String)?
}

extension AuthorizationProvider {
    public func httpAuthorizationHeader(for url: URL) -> String? {
        guard let (user, password) = self.authentication(for: url) else {
            return nil
        }
        let authString = "\(user):\(password)"
        guard let authData = authString.data(using: .utf8) else {
            return nil
        }
        return "Basic \(authData.base64EncodedString())"
    }
}
