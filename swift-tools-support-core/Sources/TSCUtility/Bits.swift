/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

struct Bits: RandomAccessCollection {
  var buffer: Data

  var startIndex: Int { return 0 }
  var endIndex: Int { return buffer.count * 8 }

  subscript(index: Int) -> UInt8 {
    let byte = buffer[index / 8]
    return (byte >> UInt8(index % 8)) & 1
  }

  func readBits(atOffset offset: Int, count: Int) -> UInt64 {
    precondition(count >= 0 && count <= 64)
    precondition(offset >= 0)
    precondition(offset &+ count >= offset)
    precondition(offset &+ count <= self.endIndex)

    return buffer.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
      let upperBound = offset &+ count
      let topByteIndex = upperBound >> 3
      var result: UInt64 = 0
      if upperBound & 7 != 0 {
        let mask: UInt8 = (1 << UInt8(upperBound & 7)) &- 1
        result = UInt64(bytes[topByteIndex] & mask)
      }
      for i in ((offset >> 3)..<(upperBound >> 3)).reversed() {
        result <<= 8
        result |= UInt64(bytes[i])
      }
      if offset & 7 != 0 {
        result >>= UInt64(offset & 7)
      }
      return result
    }
  }

  struct Cursor {
    enum Error: Swift.Error { case bufferOverflow }

    let buffer: Bits
    private var offset: Int = 0

    init(buffer: Bits) {
      self.buffer = buffer
    }
    
    init(buffer: Data) {
      self.init(buffer: Bits(buffer: buffer))
    }

    var isAtEnd: Bool {
      return offset == buffer.count
    }

    func peek(_ count: Int) throws -> UInt64 {
      if buffer.count - offset < count { throw Error.bufferOverflow }
      return buffer.readBits(atOffset: offset, count: count)
    }

    mutating func read(_ count: Int) throws -> UInt64 {
      defer { offset += count }
      return try peek(count)
    }

    mutating func read(bytes count: Int) throws -> Data {
      precondition(count >= 0)
      precondition(offset & 0b111 == 0)
      let newOffset = offset &+ (count << 3)
      precondition(newOffset >= offset)
      if newOffset > buffer.count { throw Error.bufferOverflow }
      defer { offset = newOffset }
      return buffer.buffer.dropFirst(offset >> 3).prefix((newOffset - offset) >> 3)
    }

    mutating func advance(toBitAlignment align: Int) throws {
      precondition(align > 0)
      precondition(offset &+ (align&-1) >= offset)
      precondition(align & (align &- 1) == 0)
      if offset % align == 0 { return }
      offset = (offset &+ align) & ~(align &- 1)
      if offset > buffer.count { throw Error.bufferOverflow }
    }
  }
}
