//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
public import SWBBuildServerProtocol

@_spi(Testing) public enum JSONRPCMessage {
  case notification(NotificationType)
  case request(_RequestType, id: RequestID)
  case response(ResponseType, id: RequestID)
  case errorResponse(ResponseError, id: RequestID?)
}

extension CodingUserInfoKey {
  public static let responseTypeCallbackKey: CodingUserInfoKey = CodingUserInfoKey(
    rawValue: "lsp.jsonrpc.responseTypeCallback"
  )!
  public static let messageRegistryKey: CodingUserInfoKey = CodingUserInfoKey(rawValue: "lsp.jsonrpc.messageRegistry")!
}

extension JSONRPCMessage: Codable {

  public typealias ResponseTypeCallback = @Sendable (RequestID) -> ResponseType.Type?

  private enum CodingKeys: String, CodingKey {
    case jsonrpc
    case method
    case id
    case params
    case result
    case error
  }

  public init(from decoder: Decoder) throws {

    guard let messageRegistry = decoder.userInfo[.messageRegistryKey] as? MessageRegistry else {
      fatalError("missing or invalid messageRegistryKey on decoder")
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let jsonrpc = try container.decodeIfPresent(String.self, forKey: .jsonrpc)
    let id = try container.decodeIfPresent(RequestID.self, forKey: .id)
    var msgKind = MessageDecodingError.MessageKind.unknown

    if jsonrpc != "2.0" {
      throw MessageDecodingError.invalidRequest("jsonrpc version must be 2.0")
    }

    do {
      let method = try container.decodeIfPresent(String.self, forKey: .method)
      let error = try container.decodeIfPresent(ResponseError.self, forKey: .error)

      let hasResult = container.contains(.result)

      switch (id, method, hasResult, error) {
      case (nil, let method?, _, nil):
        msgKind = .notification

        guard let messageType = messageRegistry.notificationType(for: method) else {
          throw MessageDecodingError.methodNotFound(method)
        }

        let params = try messageType.init(from: container.superDecoder(forKey: .params))

        self = .notification(params)

      case (let id?, let method?, _, nil):
        msgKind = .request

        guard let messageType = messageRegistry.requestType(for: method) else {
          throw MessageDecodingError.methodNotFound(method)
        }

        let params = try messageType.init(from: container.superDecoder(forKey: .params))

        self = .request(params, id: id)

      case (let id?, nil, true, nil):
        msgKind = .response

        guard let responseTypeCallback = decoder.userInfo[.responseTypeCallbackKey] as? ResponseTypeCallback else {
          fatalError("missing or invalid responseTypeCallbackKey on decoder")
        }

        guard let responseType = responseTypeCallback(id) else {
          throw MessageDecodingError.invalidParams("response to unknown request \(id)")
        }

        let result = try responseType.init(from: container.superDecoder(forKey: .result))

        self = .response(result, id: id)

      case (let id, nil, _, let error?):
        msgKind = .response
        self = .errorResponse(error, id: id)

      default:
        throw MessageDecodingError.invalidRequest("message not recognized as request, response or notification")
      }

    } catch var error as MessageDecodingError {
      assert(error.id == nil || error.id == id)
      error.id = id
      error.messageKind = msgKind
      throw error

    } catch DecodingError.keyNotFound(let key, _) {
      throw MessageDecodingError.invalidParams(
        "missing expected parameter: \(key.stringValue)",
        id: id,
        messageKind: msgKind
      )

    } catch DecodingError.valueNotFound(_, let context) {
      throw MessageDecodingError.invalidParams(
        "missing expected parameter: \(context.codingPath.last?.stringValue ?? "unknown")",
        id: id,
        messageKind: msgKind
      )

    } catch DecodingError.typeMismatch(_, let context) {
      let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
      throw MessageDecodingError.invalidParams(
        "type mismatch at \(path) : \(context.debugDescription)",
        id: id,
        messageKind: msgKind
      )

    } catch {
      throw MessageDecodingError.parseError(error.localizedDescription, id: id, messageKind: msgKind)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode("2.0", forKey: .jsonrpc)

    switch self {
    case .notification(let params):
      try container.encode(type(of: params).method, forKey: .method)
      try params.encode(to: container.superEncoder(forKey: .params))

    case .request(let params, let id):
      try container.encode(type(of: params).method, forKey: .method)
      try container.encode(id, forKey: .id)
      try params.encode(to: container.superEncoder(forKey: .params))

    case .response(let result, let id):
      try container.encode(id, forKey: .id)
      try result.encode(to: container.superEncoder(forKey: .result))

    case .errorResponse(let error, let id):
      try container.encode(id, forKey: .id)
      try container.encode(error, forKey: .error)
    }
  }
}
