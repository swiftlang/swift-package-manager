//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Vapor

func jsonBody(_ raw: String) -> ByteBuffer {
    ByteBuffer(string: raw)
}

func authorizationHeaders(_ value: String) -> HTTPHeaders {
    var headers = HTTPHeaders()
    headers.replaceOrAdd(name: .authorization, value: value)
    return headers
}

func basicHeaders(email: String, password: String) -> HTTPHeaders {
    authorizationHeaders("Basic \(base64Encode("\(email):\(password)"))")
}

func bearerHeaders(_ token: String) -> HTTPHeaders {
    authorizationHeaders("Bearer \(token)")
}

func base64Encode(_ string: String) -> String {
    Data(string.utf8).base64EncodedString()
}
