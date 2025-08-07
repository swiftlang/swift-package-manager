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
import SWBBuildServerProtocol

public struct JSONRPCMessageHeader: Hashable {
  static let contentLengthKey: [UInt8] = [UInt8]("Content-Length".utf8)
  static let separator: [UInt8] = [UInt8]("\r\n".utf8)
  static let colon: UInt8 = UInt8(ascii: ":")
  static let invalidKeyBytes: [UInt8] = [colon] + separator

  public var contentLength: Int? = nil

  public init(contentLength: Int? = nil) {
    self.contentLength = contentLength
  }
}

extension RandomAccessCollection<UInt8> where Index == Int {
  /// Tries to parse a single message from this collection of bytes.
  ///
  /// If an entire message could be found, returns
  ///  - header (representing `Content-Length:<length>\r\n\r\n`)
  ///  - message: The data that represents the actual message as JSON
  ///  - rest: The remaining bytes that haven't weren't part of the first message in this collection
  ///
  /// If a `Content-Length` header could be found but the collection doesn't have enough bytes for the entire message
  /// (eg. because the `Content-Length` header has been transmitted yet but not the entire message), returns `nil`.
  /// Callers should call this method again once more data is available.
  @_spi(Testing)
  public func jsonrpcSplitMessage() throws -> (header: JSONRPCMessageHeader, message: SubSequence, rest: SubSequence)? {
    guard let (header, rest) = try jsonrcpParseHeader() else { return nil }
    guard let contentLength = header.contentLength else {
      throw MessageDecodingError.parseError("missing Content-Length header")
    }
    if contentLength > rest.count { return nil }
    return (header: header, message: rest.prefix(contentLength), rest: rest.dropFirst(contentLength))
  }

  @_spi(Testing)
  public func jsonrcpParseHeader() throws -> (header: JSONRPCMessageHeader, rest: SubSequence)? {
    var header = JSONRPCMessageHeader()
    var slice = self[...]
    while let (kv, rest) = try slice.jsonrpcParseHeaderField() {
      guard let (key, value) = kv else {
        return (header, rest)
      }
      slice = rest

      if key.elementsEqual(JSONRPCMessageHeader.contentLengthKey) {
        guard let count = Int(ascii: value) else {
          throw MessageDecodingError.parseError(
            "expected integer value in \(String(bytes: value, encoding: .utf8) ?? "<invalid>")"
          )
        }
        header.contentLength = count
      }

      // Unknown field, continue.
    }
    return nil
  }

  @_spi(Testing)
  public func jsonrpcParseHeaderField() throws -> ((key: SubSequence, value: SubSequence)?, SubSequence)? {
    if starts(with: JSONRPCMessageHeader.separator) {
      return (nil, dropFirst(JSONRPCMessageHeader.separator.count))
    } else if first == JSONRPCMessageHeader.separator.first {
      return nil
    }

    guard let keyEnd = firstIndex(where: { JSONRPCMessageHeader.invalidKeyBytes.contains($0) }) else {
      return nil
    }
    if self[keyEnd] != JSONRPCMessageHeader.colon {
      throw MessageDecodingError.parseError("expected ':' in message header")
    }
    let valueStart = index(after: keyEnd)
    guard let valueEnd = self[valueStart...].firstRange(of: JSONRPCMessageHeader.separator)?.startIndex else {
      return nil
    }

    return ((key: self[..<keyEnd], value: self[valueStart..<valueEnd]), self[index(valueEnd, offsetBy: 2)...])
  }
}

extension UInt8 {
  /// *Public for *testing*. Whether this byte is an ASCII whitespace character (isspace).
  @inlinable
  public var isSpace: Bool {
    switch self {
    case UInt8(ascii: " "), UInt8(ascii: "\t"), /*LF*/ 0xa, /*VT*/ 0xb, /*FF*/ 0xc, /*CR*/ 0xd:
      return true
    default:
      return false
    }
  }

  /// *Public for *testing*. Whether this byte is an ASCII decimal digit (isdigit).
  @inlinable
  public var isDigit: Bool {
    return UInt8(ascii: "0") <= self && self <= UInt8(ascii: "9")
  }

  /// *Public for *testing*. The integer value of an ASCII decimal digit.
  @inlinable
  public var asciiDigit: Int {
    precondition(isDigit)
    return Int(self - UInt8(ascii: "0"))
  }
}

extension Int {

  /// Constructs an integer from a buffer of base-10 ascii digits, ignoring any surrounding whitespace.
  ///
  /// This is similar to `atol` but with several advantages:
  /// - no need to construct a null-terminated C string
  /// - overflow will trap instead of being undefined
  /// - does not allow non-whitespace characters at the end
  @inlinable
  public init?<C>(ascii buffer: C) where C: Collection, C.Element == UInt8 {
    guard !buffer.isEmpty else { return nil }

    // Trim leading whitespace.
    var i = buffer.startIndex
    while i != buffer.endIndex, buffer[i].isSpace {
      i = buffer.index(after: i)
    }

    guard i != buffer.endIndex else { return nil }

    // Check sign if any.
    var sign = 1
    if buffer[i] == UInt8(ascii: "+") {
      i = buffer.index(after: i)
    } else if buffer[i] == UInt8(ascii: "-") {
      i = buffer.index(after: i)
      sign = -1
    }

    guard i != buffer.endIndex, buffer[i].isDigit else { return nil }

    // Accumulate the result.
    var result = 0
    while i != buffer.endIndex, buffer[i].isDigit {
      result = result * 10 + sign * buffer[i].asciiDigit
      i = buffer.index(after: i)
    }

    // Trim trailing whitespace.
    while i != buffer.endIndex {
      if !buffer[i].isSpace { return nil }
      i = buffer.index(after: i)
    }
    self = result
  }

  // Constructs an integer from a buffer of base-10 ascii digits, ignoring any surrounding whitespace.
  ///
  /// This is similar to `atol` but with several advantages:
  /// - no need to construct a null-terminated C string
  /// - overflow will trap instead of being undefined
  /// - does not allow non-whitespace characters at the end
  @inlinable
  public init?<S>(ascii buffer: S) where S: StringProtocol {
    self.init(ascii: buffer.utf8)
  }
}
