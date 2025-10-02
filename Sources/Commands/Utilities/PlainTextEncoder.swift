//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.Data
import class TSCBasic.BufferedOutputByteStream
import protocol TSCBasic.OutputByteStream

struct PlainTextEncoder {
    /// The formatting of the output plain-text data.
    struct FormattingOptions: OptionSet {
        let rawValue: UInt

        init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        /// Produce plain-text format with indented output.
        static let prettyPrinted = FormattingOptions(rawValue: 1 << 0)
    }

    /// The output format to produce. Defaults to `[]`.
    var formattingOptions: FormattingOptions = []

    /// Contextual user-provided information for use during encoding.
    var userInfo: [CodingUserInfoKey: Any] = [:]

    /// Encodes the given top-level value and returns its plain text representation.
    ///
    /// - parameter value: The value to encode.
    /// - returns: A new `Data` value containing the encoded plan-text data.
    /// - throws: An error if any value throws an error during encoding.
    func encode<T: Encodable>(_ value: T) throws -> Data {
        let outputStream = BufferedOutputByteStream()
        let encoder = _PlainTextEncoder(
            outputStream: outputStream,
            formattingOptions: formattingOptions,
            userInfo: userInfo
        )
        try value.encode(to: encoder)
        return Data(outputStream.bytes.contents)
    }

    /// Private helper function to format key names with an uppercase initial letter and space-separated components.
    private static func displayName(for key: CodingKey) -> String {
        var result = ""
        for ch in key.stringValue {
            if result.isEmpty {
                result.append(ch.uppercased())
            }
            else if ch.isUppercase {
                result.append(" ")
                result.append(ch.lowercased())
            }
            else {
                result.append(ch)
            }
        }
        return result
    }

    /// Private Encoder implementation for PlainTextEncoder.
    private struct _PlainTextEncoder: Encoder {
        /// Output stream.
        var outputStream: OutputByteStream

        /// Formatting options set on the top-level encoder.
        let formattingOptions: PlainTextEncoder.FormattingOptions

        /// Contextual user-provided information for use during encoding.
        let userInfo: [CodingUserInfoKey: Any]

        /// The path to the current point in encoding.
        let codingPath: [CodingKey]

        /// Initializes `self` with the given top-level encoder options.
        init(outputStream: OutputByteStream, formattingOptions: PlainTextEncoder.FormattingOptions, userInfo: [CodingUserInfoKey: Any], codingPath: [CodingKey] = []) {
            self.outputStream = outputStream
            self.formattingOptions = formattingOptions
            self.userInfo = userInfo
            self.codingPath = codingPath
        }

        func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
            return KeyedEncodingContainer(PlainTextKeyedEncodingContainer<Key>(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath))
        }

        func unkeyedContainer() -> UnkeyedEncodingContainer {
            return PlainTextUnkeyedEncodingContainer(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath)
        }

        func singleValueContainer() -> SingleValueEncodingContainer {
            return TextSingleValueEncodingContainer(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath)
        }

        /// Private KeyedEncodingContainer implementation for PlainTextEncoder.
        private struct PlainTextKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
            let outputStream: OutputByteStream
            let formattingOptions: PlainTextEncoder.FormattingOptions
            let userInfo: [CodingUserInfoKey: Any]
            let codingPath: [CodingKey]

            private mutating func emit(_ key: CodingKey, _ value: String?) {
                outputStream.send("\(String(repeating: "    ", count: codingPath.count))\(displayName(for: key)):")
                if let value { outputStream.send(" \(value)") }
                outputStream.send("\n")
            }
            mutating func encodeNil(forKey key: Key) throws { emit(key, "nil") }
            mutating func encode(_ value: Bool, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: String, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Double, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Float, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Int, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Int8, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Int16, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Int32, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: Int64, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: UInt, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: UInt8, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: UInt16, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: UInt32, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode(_ value: UInt64, forKey key: Key) throws { emit(key, "\(value)") }
            mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
                emit(key, nil)
                let textEncoder = _PlainTextEncoder(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath + [key])
                try value.encode(to: textEncoder)
            }

            mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
                emit(key, nil)
                return KeyedEncodingContainer(PlainTextKeyedEncodingContainer<NestedKey>(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath + [key]))
            }

            mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
                emit(key, nil)
                return PlainTextUnkeyedEncodingContainer(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath + [key])
            }

            mutating func superEncoder() -> Encoder {
                return superEncoder(forKey: Key(stringValue: "super")!)
            }

            mutating func superEncoder(forKey key: Key) -> Encoder {
                return _PlainTextEncoder(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath + [key])
            }
        }

        /// Private UnkeyedEncodingContainer implementation for PlainTextEncoder.
        private struct PlainTextUnkeyedEncodingContainer: UnkeyedEncodingContainer {
            let outputStream: OutputByteStream
            let formattingOptions: PlainTextEncoder.FormattingOptions
            let userInfo: [CodingUserInfoKey: Any]
            let codingPath: [CodingKey]
            private(set) var count: Int = 0

            private mutating func emit(_ value: String) {
                outputStream.send("\(String(repeating: "    ", count: codingPath.count))\(value)\n")
                count += 1
            }
            mutating func encodeNil() throws { emit("nil") }
            mutating func encode(_ value: Bool) throws { emit("\(value)") }
            mutating func encode(_ value: String) throws { emit("\(value)") }
            mutating func encode(_ value: Double) throws { emit("\(value)") }
            mutating func encode(_ value: Float) throws { emit("\(value)") }
            mutating func encode(_ value: Int) throws { emit("\(value)") }
            mutating func encode(_ value: Int8) throws { emit("\(value)") }
            mutating func encode(_ value: Int16) throws { emit("\(value)") }
            mutating func encode(_ value: Int32) throws { emit("\(value)") }
            mutating func encode(_ value: Int64) throws { emit("\(value)") }
            mutating func encode(_ value: UInt) throws { emit("\(value)") }
            mutating func encode(_ value: UInt8) throws { emit("\(value)") }
            mutating func encode(_ value: UInt16) throws { emit("\(value)") }
            mutating func encode(_ value: UInt32) throws { emit("\(value)") }
            mutating func encode(_ value: UInt64) throws { emit("\(value)") }
            mutating func encode<T: Encodable>(_ value: T) throws {
                let textEncoder = _PlainTextEncoder(
                    outputStream: outputStream,
                    formattingOptions: formattingOptions,
                    userInfo: userInfo,
                    codingPath: codingPath
                )
                try value.encode(to: textEncoder)
                count += 1
                // FIXME: This is a bit arbitrary and should be controllable.  We may also want an option to only emit
                // newlines between entries, not after each one.
                if codingPath.count < 2 { outputStream.send("\n") }
            }

            mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
                KeyedEncodingContainer(PlainTextKeyedEncodingContainer<NestedKey>(
                    outputStream: outputStream,
                    formattingOptions: formattingOptions,
                    userInfo: userInfo,
                    codingPath: codingPath
                ))
            }

            mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
                return PlainTextUnkeyedEncodingContainer(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath)
            }

            mutating func superEncoder() -> Encoder {
                return _PlainTextEncoder(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath)
            }
        }

        /// Private SingleValueEncodingContainer implementation for PlainTextEncoder.
        private struct TextSingleValueEncodingContainer: SingleValueEncodingContainer {
            let outputStream: OutputByteStream
            let formattingOptions: PlainTextEncoder.FormattingOptions
            let userInfo: [CodingUserInfoKey: Any]
            let codingPath: [CodingKey]

            private mutating func emit(_ value: String) {
                outputStream.send("\(String(repeating: "    ", count: codingPath.count))\(value)\n")
            }
            mutating func encodeNil() throws { emit("nil") }
            mutating func encode(_ value: Bool) throws { emit("\(value)") }
            mutating func encode(_ value: String) throws { emit("\(value)") }
            mutating func encode(_ value: Double) throws { emit("\(value)") }
            mutating func encode(_ value: Float) throws { emit("\(value)") }
            mutating func encode(_ value: Int) throws { emit("\(value)") }
            mutating func encode(_ value: Int8) throws { emit("\(value)") }
            mutating func encode(_ value: Int16) throws { emit("\(value)") }
            mutating func encode(_ value: Int32) throws { emit("\(value)") }
            mutating func encode(_ value: Int64) throws { emit("\(value)") }
            mutating func encode(_ value: UInt) throws { emit("\(value)") }
            mutating func encode(_ value: UInt8) throws { emit("\(value)") }
            mutating func encode(_ value: UInt16) throws { emit("\(value)") }
            mutating func encode(_ value: UInt32) throws { emit("\(value)") }
            mutating func encode(_ value: UInt64) throws { emit("\(value)") }
            mutating func encode<T: Encodable>(_ value: T) throws {
                let textEncoder = _PlainTextEncoder(outputStream: outputStream, formattingOptions: formattingOptions, userInfo: userInfo, codingPath: codingPath)
                try value.encode(to: textEncoder)
            }
        }
    }
}
