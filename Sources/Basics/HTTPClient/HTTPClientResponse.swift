//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

public struct HTTPClientResponse: Sendable {
    public let statusCode: Int
    public let statusText: String?
    public let headers: HTTPClientHeaders
    public let body: Data?

    public init(
        statusCode: Int,
        statusText: String? = nil,
        headers: HTTPClientHeaders = .init(),
        body: Data? = nil
    ) {
        self.statusCode = statusCode
        self.statusText = statusText
        self.headers = headers
        self.body = body
    }

    public func decodeBody<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = .init()) throws -> T? {
        try self.body.flatMap { try decoder.decode(type, from: $0) }
    }
}

extension HTTPClientResponse {
    public static func okay(body: String? = nil) -> HTTPClientResponse {
        .okay(body: body.map { Data($0.utf8) })
    }

    public static func okay(body: Data?) -> HTTPClientResponse {
        HTTPClientResponse(statusCode: 200, body: body)
    }

    public static func notFound(reason: String? = nil) -> HTTPClientResponse {
        HTTPClientResponse(statusCode: 404, body: Data((reason ?? "Not Found").utf8))
    }

    public static func serverError(reason: String? = nil) -> HTTPClientResponse {
        HTTPClientResponse(statusCode: 500, body: Data((reason ?? "Internal Server Error").utf8))
    }
}
