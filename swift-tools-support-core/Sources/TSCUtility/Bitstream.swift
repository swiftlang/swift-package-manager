/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

public enum BitcodeElement {
  public struct Block {
    public var id: UInt64
    public var elements: [BitcodeElement]
  }

  public struct Record {
    public enum Payload {
      case none
      case array([UInt64])
      case char6String(String)
      case blob(Data)
    }

    public var id: UInt64
    public var fields: [UInt64]
    public var payload: Payload
  }

  case block(Block)
  case record(Record)
}

public struct BlockInfo {
  public var name: String = ""
  public var recordNames: [UInt64: String] = [:]
}

extension Bitcode {
  public struct Signature: Equatable {
    private var value: UInt32

    public init(value: UInt32) {
      self.value = value
    }

    public init(string: String) {
      precondition(string.utf8.count == 4)
      var result: UInt32 = 0
      for byte in string.utf8.reversed() {
        result <<= 8
        result |= UInt32(byte)
      }
      self.value = result
    }
  }
}

/// Represents the contents of a file encoded using the
/// [LLVM bitstream container format](https://llvm.org/docs/BitCodeFormat.html#bitstream-container-format)
public struct Bitcode {
  public let signature: Signature
  public let elements: [BitcodeElement]
  public let blockInfo: [UInt64: BlockInfo]
}

private extension Bits.Cursor {
  enum BitcodeError: Swift.Error {
    case vbrOverflow
  }

  mutating func readVBR(_ width: Int) throws -> UInt64 {
    precondition(width > 1)
    let testBit = UInt64(1 << (width &- 1))
    let mask = testBit &- 1

    var result: UInt64 = 0
    var offset: UInt64 = 0
    var next: UInt64
    repeat {
      next = try self.read(width)
      result |= (next & mask) << offset
      offset += UInt64(width &- 1)
      if offset > 64 { throw BitcodeError.vbrOverflow }
    } while next & testBit != 0

    return result
  }
}

private struct BitstreamReader {
  struct Abbrev {
    enum Operand {
      case literal(UInt64)
      case fixed(Int)
      case vbr(Int)
      indirect case array(Operand)
      case char6
      case blob

      var isPayload: Bool {
        switch self {
        case .array, .blob: return true
        case .literal, .fixed, .vbr, .char6: return false
        }
      }
    }

    var operands: [Operand] = []
  }

  enum Error: Swift.Error {
    case invalidAbbrev
    case nestedBlockInBlockInfo
    case missingSETBID
    case invalidBlockInfoRecord(recordID: UInt64)
    case abbrevWidthTooSmall(width: Int)
    case noSuchAbbrev(blockID: UInt64, abbrevID: Int)
    case missingEndBlock(blockID: UInt64)
  }

  var cursor: Bits.Cursor
  var blockInfo: [UInt64: BlockInfo] = [:]
  var globalAbbrevs: [UInt64: [Abbrev]] = [:]

  init(buffer: Data) {
    cursor = Bits.Cursor(buffer: buffer)
  }

  mutating func readAbbrevOp() throws -> Abbrev.Operand {
    let isLiteralFlag = try cursor.read(1)
    if isLiteralFlag == 1 {
      return .literal(try cursor.readVBR(8))
    }

    switch try cursor.read(3) {
    case 0:
      throw Error.invalidAbbrev
    case 1:
      return .fixed(Int(try cursor.readVBR(5)))
    case 2:
      return .vbr(Int(try cursor.readVBR(5)))
    case 3:
      return .array(try readAbbrevOp())
    case 4:
      return .char6
    case 5:
      return .blob
    case 6, 7:
      throw Error.invalidAbbrev
    default:
      fatalError()
    }
  }

  mutating func readAbbrev(numOps: Int) throws -> Abbrev {
    guard numOps > 0 else { throw Error.invalidAbbrev }

    var operands: [Abbrev.Operand] = []
    for i in 0..<numOps {
      operands.append(try readAbbrevOp())

      if case .array = operands.last! {
        guard i == numOps - 2 else { throw Error.invalidAbbrev }
        break
      } else if case .blob = operands.last! {
        guard i == numOps - 1 else { throw Error.invalidAbbrev }
      }
    }

    return Abbrev(operands: operands)
  }

  mutating func readSingleAbbreviatedRecordOperand(_ operand: Abbrev.Operand) throws -> UInt64 {
    switch operand {
    case .char6:
      let value = try cursor.read(6)
      switch value {
      case 0...25:
        return value + UInt64(("a" as UnicodeScalar).value)
      case 26...51:
        return value + UInt64(("A" as UnicodeScalar).value) - 26
      case 52...61:
        return value + UInt64(("0" as UnicodeScalar).value) - 52
      case 62:
        return UInt64(("." as UnicodeScalar).value)
      case 63:
        return UInt64(("_" as UnicodeScalar).value)
      default:
        fatalError()
      }
    case .literal(let value):
      return value
    case .fixed(let width):
      return try cursor.read(width)
    case .vbr(let width):
      return try cursor.readVBR(width)
    case .array, .blob:
      fatalError()
    }
  }

  mutating func readAbbreviatedRecord(_ abbrev: Abbrev) throws -> BitcodeElement.Record {
    let code = try readSingleAbbreviatedRecordOperand(abbrev.operands.first!)

    let lastOperand = abbrev.operands.last!
    let lastRegularOperandIndex: Int = abbrev.operands.endIndex - (lastOperand.isPayload ? 1 : 0)

    var fields = [UInt64]()
    for op in abbrev.operands[1..<lastRegularOperandIndex] {
      fields.append(try readSingleAbbreviatedRecordOperand(op))
    }

    let payload: BitcodeElement.Record.Payload
    if !lastOperand.isPayload {
      payload = .none
    } else {
      switch lastOperand {
      case .array(let element):
        let length = try cursor.readVBR(6)
        var elements = [UInt64]()
        for _ in 0..<length {
          elements.append(try readSingleAbbreviatedRecordOperand(element))
        }
        if case .char6 = element {
          payload = .char6String(String(String.UnicodeScalarView(elements.map { UnicodeScalar(UInt8($0)) })))
        } else {
          payload = .array(elements)
        }
      case .blob:
        let length = Int(try cursor.readVBR(6))
        try cursor.advance(toBitAlignment: 32)
        payload = .blob(try cursor.read(bytes: length))
        try cursor.advance(toBitAlignment: 32)
      default:
        fatalError()
      }
    }

    return .init(id: code, fields: fields, payload: payload)
  }

  mutating func readBlockInfoBlock(abbrevWidth: Int) throws {
    var currentBlockID: UInt64?
    while true {
      switch try cursor.read(abbrevWidth) {
      case 0: // END_BLOCK
        try cursor.advance(toBitAlignment: 32)
        // FIXME: check expected length
        return

      case 1: // ENTER_BLOCK
        throw Error.nestedBlockInBlockInfo

      case 2: // DEFINE_ABBREV
        guard let blockID = currentBlockID else {
          throw Error.missingSETBID
        }
        let numOps = Int(try cursor.readVBR(5))
        if globalAbbrevs[blockID] == nil { globalAbbrevs[blockID] = [] }
        globalAbbrevs[blockID]!.append(try readAbbrev(numOps: numOps))

      case 3: // UNABBREV_RECORD
        let code = try cursor.readVBR(6)
        let numOps = try cursor.readVBR(6)
        var operands = [UInt64]()
        for _ in 0..<numOps {
          operands.append(try cursor.readVBR(6))
        }

        switch code {
        case 1:
          guard operands.count == 1 else { throw Error.invalidBlockInfoRecord(recordID: code) }
          currentBlockID = operands.first
        case 2:
          guard let blockID = currentBlockID else {
            throw Error.missingSETBID
          }
          if blockInfo[blockID] == nil { blockInfo[blockID] = BlockInfo() }
          blockInfo[blockID]!.name = String(bytes: operands.map { UInt8($0) }, encoding: .utf8) ?? "<invalid>"
        case 3:
          guard let blockID = currentBlockID else {
            throw Error.missingSETBID
          }
          if blockInfo[blockID] == nil { blockInfo[blockID] = BlockInfo() }
          guard let recordID = operands.first else {
            throw Error.invalidBlockInfoRecord(recordID: code)
          }
          blockInfo[blockID]!.recordNames[recordID] = String(bytes: operands.dropFirst().map { UInt8($0) }, encoding: .utf8) ?? "<invalid>"
        default:
          throw Error.invalidBlockInfoRecord(recordID: code)
        }

      case let abbrevID:
        throw Error.noSuchAbbrev(blockID: 0, abbrevID: Int(abbrevID))
      }
    }
  }

  mutating func readBlock<Visitor: BitstreamVisitor>(id: UInt64, abbrevWidth: Int, abbrevInfo: [Abbrev], visitor: inout Visitor) throws {
    var abbrevInfo = abbrevInfo

    while !cursor.isAtEnd {
      switch try cursor.read(abbrevWidth) {
      case 0: // END_BLOCK
        try cursor.advance(toBitAlignment: 32)
        // FIXME: check expected length
        try visitor.didExitBlock()
        return

      case 1: // ENTER_SUBBLOCK
        let blockID = try cursor.readVBR(8)
        let newAbbrevWidth = Int(try cursor.readVBR(4))
        try cursor.advance(toBitAlignment: 32)
        let blockLength = try cursor.read(32) * 4

        switch blockID {
        case 0:
          try readBlockInfoBlock(abbrevWidth: newAbbrevWidth)
        case 1...7:
          // Metadata blocks we don't understand yet
          fallthrough
        default:
          guard try visitor.shouldEnterBlock(id: blockID) else {
            try cursor.skip(bytes: Int(blockLength))
            break
          }
          try readBlock(
            id: blockID, abbrevWidth: newAbbrevWidth,
            abbrevInfo: globalAbbrevs[blockID] ?? [], visitor: &visitor)
        }

      case 2: // DEFINE_ABBREV
        let numOps = Int(try cursor.readVBR(5))
        abbrevInfo.append(try readAbbrev(numOps: numOps))

      case 3: // UNABBREV_RECORD
        let code = try cursor.readVBR(6)
        let numOps = try cursor.readVBR(6)
        var operands = [UInt64]()
        for _ in 0..<numOps {
          operands.append(try cursor.readVBR(6))
        }
        try visitor.visit(record: .init(id: code, fields: operands, payload: .none))

      case let abbrevID:
        guard Int(abbrevID) - 4 < abbrevInfo.count else {
          throw Error.noSuchAbbrev(blockID: id, abbrevID: Int(abbrevID))
        }
        try visitor.visit(record: try readAbbreviatedRecord(abbrevInfo[Int(abbrevID) - 4]))
      }
    }

    guard id == Self.fakeTopLevelBlockID else {
      throw Error.missingEndBlock(blockID: id)
    }
  }

  static let fakeTopLevelBlockID: UInt64 = ~0
}

/// A visitor which receives callbacks while reading a bitstream.
public protocol BitstreamVisitor {
  /// Customization point to validate a bitstream's signature or "magic number".
  func validate(signature: Bitcode.Signature) throws
  /// Called when a new block is encountered. Return `true` to enter the block
  /// and read its contents, or `false` to skip it.
  mutating func shouldEnterBlock(id: UInt64) throws -> Bool
  /// Called when a block is exited.
  mutating func didExitBlock() throws
  /// Called whenever a record is encountered.
  mutating func visit(record: BitcodeElement.Record) throws
}

/// A basic visitor that collects all the blocks and records in a stream.
private struct CollectingVisitor: BitstreamVisitor {
  var stack: [(UInt64, [BitcodeElement])] = [(BitstreamReader.fakeTopLevelBlockID, [])]

  func validate(signature: Bitcode.Signature) throws {}

  mutating func shouldEnterBlock(id: UInt64) throws -> Bool {
    stack.append((id, []))
    return true
  }

  mutating func didExitBlock() throws {
    guard let (id, elements) = stack.popLast() else {
      fatalError("Unbalanced calls to shouldEnterBlock/didExitBlock")
    }

    let block = BitcodeElement.Block(id: id, elements: elements)
    stack[stack.endIndex-1].1.append(.block(block))
  }

  mutating func visit(record: BitcodeElement.Record) throws {
    stack[stack.endIndex-1].1.append(.record(record))
  }

  func finalizeTopLevelElements() -> [BitcodeElement] {
    assert(stack.count == 1)
    return stack[0].1
  }
}

extension Bitcode {
  /// Parse a bitstream from data.
  public init(data: Data) throws {
    precondition(data.count > 4)
    let signatureValue = UInt32(Bits(buffer: data).readBits(atOffset: 0, count: 32))
    let bitstreamData = data[4..<data.count]

    var reader = BitstreamReader(buffer: bitstreamData)
    var visitor = CollectingVisitor()
    try reader.readBlock(id: BitstreamReader.fakeTopLevelBlockID,
                         abbrevWidth: 2,
                         abbrevInfo: [],
                         visitor: &visitor)
    self.init(signature: .init(value: signatureValue),
              elements: visitor.finalizeTopLevelElements(),
              blockInfo: reader.blockInfo)
  }

  /// Traverse a bitstream using the specified `visitor`, which will receive
  /// callbacks when blocks and records are encountered.
  public static func read<Visitor: BitstreamVisitor>(stream data: Data, using visitor: inout Visitor) throws {
    precondition(data.count > 4)
    let signatureValue = UInt32(Bits(buffer: data).readBits(atOffset: 0, count: 32))
    try visitor.validate(signature: .init(value: signatureValue))

    let bitstreamData = data[4..<data.count]
    var reader = BitstreamReader(buffer: bitstreamData)
    try reader.readBlock(id: BitstreamReader.fakeTopLevelBlockID,
                         abbrevWidth: 2,
                         abbrevInfo: [],
                         visitor: &visitor)
  }
}
