// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import Foundation


extension ArraySlice where Element == UInt8 {

    /// String representation of a Base64URL-encoded `ArraySlice<UInt8>`.
    public func base64URL() -> String {
        return base64URL(prepending: [])
    }

    public func base64URL(prepending: [UInt8]) -> String {
        var offset = 0
        var recorded = 0
        let base64URLCount = ((count * 4 / 3) + 3) & ~3
        var arr = [UInt8](repeating: UInt8(ascii: "="), count: prepending.count + base64URLCount)
        self.withUnsafeBytes { from in
          arr.withUnsafeMutableBytes { to_ in
            var to = Base64URLAppendable(to_.baseAddress!)
            to.append(prepending)
            while true {
              switch self.count - offset {
              case let n where n >= 3:
                to.add = from[offset] >> 2
                to.add = from[offset] << 4 | from[offset+1] >> 4
                to.add = from[offset+1] << 2 | from[offset+2] >> 6
                to.add = from[offset+2]
                offset += 3
                recorded += 4
              case 2:
                to.add = from[offset] >> 2
                to.add = from[offset] << 4 | from[offset+1] >> 4
                to.add = from[offset+1] << 2
                recorded += 4
                return
              case 1:
                to.add = from[offset] >> 2
                to.add = from[offset] << 4
                recorded += 4
                return
              case 0:
                return
              default:
                fatalError("can't appear here (left=\(self.count-offset))")
              }
            }
          }
        }
        assert(prepending.count + recorded == arr.count, "prepending=\(prepending.count)+recorded=\(recorded) != \(arr.count)")
        return String(bytes: arr, encoding: .ascii)!
    }

    fileprivate struct Base64URLAppendable {
        private let ptr: UnsafeMutableRawPointer
        private var offset_: Int = 0

        private static let toBase64Table: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)

        var offset: Int {
            return offset_
        }

        init(_ ptr: UnsafeMutableRawPointer) {
            self.ptr = ptr
        }

        var add: UInt8 {
            get { return 0 }
            set {
                let value: UInt8 = Base64URLAppendable.toBase64Table[Int(newValue & 0x3f)]
                ptr.storeBytes(of: value, toByteOffset: offset_, as: UInt8.self)
                offset_ += 1
            }
        }

        mutating func append(_ bytes: [UInt8]) {
            bytes.withUnsafeBytes { arg in
                let fromptr = arg.baseAddress!
                ptr.copyMemory(from: fromptr, byteCount: bytes.count)
            }
            offset_ += bytes.count
        }
    }
}

extension Array where Element == UInt8 {

    /// String representation of a Base64URL-encoded `[UInt8]`.
    public func base64URL() -> String {
        return ArraySlice(self).base64URL()
    }

    /// Base64URL encoding. Returns `nil` if the Base64URL encoding is broken.
    public init?(base64URL str: String, prepending: [UInt8] = []) {
        guard let array = [UInt8](base64URL: str[str.startIndex...]) else {
            return nil
        }
        self = array
    }

    public init?(base64URL str: Substring, prepending: [UInt8] = []) {
        var memory = [UInt8](prepending)
        memory.reserveCapacity(prepending.count + str.count * 3 / 4)

        var currentValue: UInt32 = 0
        var currentBits = 0

        for char in str.unicodeScalars {
            guard char.isASCII else {
                return nil
            }

            switch char.value {
            case let n where n >= UInt32(UInt8(ascii: "A")) && n <=  UInt32(UInt8(ascii: "Z")):
                currentValue <<= 6
                currentValue |= n - UInt32(UInt8(ascii: "A"))
                currentBits += 6
            case let n where n >= UInt32(UInt8(ascii: "a")) && n <=  UInt32(UInt8(ascii: "z")):
                currentValue <<= 6
                currentValue |= 26 + (n - UInt32(UInt8(ascii: "a")))
                currentBits += 6
            case let n where n >= UInt32(UInt8(ascii: "0")) && n <=  UInt32(UInt8(ascii: "9")):
                currentValue <<= 6
                currentValue |= 52 + (n - UInt32(UInt8(ascii: "0")))
                currentBits += 6
            case UInt32(UInt8(ascii: "-")):
                currentValue <<= 6
                currentValue |= 62
                currentBits += 6
            case UInt32(UInt8(ascii: "_")):
                currentValue <<= 6
                currentValue |= 63
                currentBits += 6
            case UInt32(UInt8(ascii: "=")):
                guard currentValue == 0 else {
                    return nil
                }
                currentBits = 0
                continue
            default:
                return nil
            }

            if currentBits >= 8 {
                currentBits -= 8
                assert(currentBits < 8)
                let byte: UInt8 = UInt8(currentValue >> currentBits)
                currentValue &= (1 << currentBits) - 1
                memory.append(byte)
            }
        }

        guard currentBits == 0 && currentValue == 0 else {
            return nil
        }

        self = memory
    }

}
