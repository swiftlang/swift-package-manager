/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic

class OutputByteStreamTests: XCTestCase {
    func testBasics() {
        let stream = BufferedOutputByteStream()
        
        stream.write("Hello")
        stream.write(Character(","))
        stream.write(Character(" "))
        stream.write([UInt8]("wor".utf8))
        stream.write([UInt8]("world".utf8)[3..<5])
        
        let streamable: TextOutputStreamable = Character("!")
        stream.write(streamable)

        
        XCTAssertEqual(stream.position, "Hello, world!".utf8.count)
        stream.flush()
        XCTAssertEqual(stream.bytes, "Hello, world!")
    }
    
    func testStreamOperator() {
        let stream = BufferedOutputByteStream()

        let streamable: TextOutputStreamable = Character("!")
        stream <<< "Hello" <<< Character(",") <<< Character(" ") <<< [UInt8]("wor".utf8) <<< [UInt8]("world".utf8)[3..<5] <<< streamable
        
        XCTAssertEqual(stream.position, "Hello, world!".utf8.count)
        XCTAssertEqual(stream.bytes, "Hello, world!")

        let stream2 = BufferedOutputByteStream()
        stream2 <<< (0..<5)
        XCTAssertEqual(stream2.bytes, [0, 1, 2, 3, 4])
    }
    
    func testBufferCorrectness() {
        let smallBlock = [UInt8](repeating: 2, count: 1 << 14)
        // Check small / big interleavings for various block sizes (to prove buffer transfer optimizations).
        for blockSize in [1 << 10, 1 << 12, 1 << 13, 1 << 14] {
            let bigBlock = [UInt8](repeating: 1, count: blockSize)

            var stream = BufferedOutputByteStream()
            stream <<< smallBlock <<< bigBlock
            XCTAssertEqual(stream.bytes, ByteString(smallBlock + bigBlock))

            stream = BufferedOutputByteStream()
            stream <<< bigBlock <<< smallBlock
            XCTAssertEqual(stream.bytes, ByteString(bigBlock + smallBlock))

            stream = BufferedOutputByteStream()
            stream <<< bigBlock <<< bigBlock
            XCTAssertEqual(stream.bytes, ByteString(bigBlock + bigBlock))
        }
    }

    func testJSONEncoding() {
        // Test string encoding.
        func asJSON(_ value: String) -> ByteString {
            let stream = BufferedOutputByteStream()
            stream.writeJSONEscaped(value)
            return stream.bytes
        }
        XCTAssertEqual(asJSON("a'\"\\"), "a'\\\"\\\\")
        XCTAssertEqual(asJSON("\u{0008}"), "\\b")
        XCTAssertEqual(asJSON("\u{000C}"), "\\f")
        XCTAssertEqual(asJSON("\n"), "\\n")
        XCTAssertEqual(asJSON("\r"), "\\r")
        XCTAssertEqual(asJSON("\t"), "\\t")
        XCTAssertEqual(asJSON("\u{0001}"), "\\u0001")

        // Test other random types.
        var stream = BufferedOutputByteStream()
        stream <<< Format.asJSON(false)
        XCTAssertEqual(stream.bytes, "false")

        stream = BufferedOutputByteStream()
        stream  <<< Format.asJSON(1 as Int)
        XCTAssertEqual(stream.bytes, "1")

        stream = BufferedOutputByteStream()
        stream <<< Format.asJSON(1.2 as Double)
        XCTAssertEqual(stream.bytes, "1.2")
    }
    
    func testFormattedOutput() {
        do {
            let stream = BufferedOutputByteStream()
            stream <<< Format.asJSON("\n")
            XCTAssertEqual(stream.bytes, "\"\\n\"")
        }
        
        do {
            let stream = BufferedOutputByteStream()
            stream <<< Format.asJSON(["hello", "world\n"])
            XCTAssertEqual(stream.bytes, "[\"hello\",\"world\\n\"]")
        }
        
        do {
            let stream = BufferedOutputByteStream()
            stream <<< Format.asJSON(["hello": "world\n"])
            XCTAssertEqual(stream.bytes, "{\"hello\":\"world\\n\"}")
        }

        do {
            struct MyThing {
                let value: String
                init(_ value: String) { self.value = value }
            }
            let stream = BufferedOutputByteStream()
            stream <<< Format.asJSON([MyThing("hello"), MyThing("world\n")], transform: { $0.value })
            XCTAssertEqual(stream.bytes, "[\"hello\",\"world\\n\"]")
        }

        do {
            let stream = BufferedOutputByteStream()
            stream <<< Format.asSeparatedList(["hello", "world"], separator: ", ")
            XCTAssertEqual(stream.bytes, "hello, world")
        }
        
        do {
            struct MyThing {
                let value: String
                init(_ value: String) { self.value = value }
            }
            let stream = BufferedOutputByteStream()
            stream <<< Format.asSeparatedList([MyThing("hello"), MyThing("world")], transform: { $0.value }, separator: ", ")
            XCTAssertEqual(stream.bytes, "hello, world")
        }
    }

    func testLocalFileStream() throws {
        let tempFile = try TemporaryFile()

        func read() -> String? {
            return try! localFileSystem.readFileContents(tempFile.path).asString
        }

        let stream = try LocalFileOutputByteStream(tempFile.path)
        stream <<< "Hello"
        stream.flush()
        XCTAssertEqual(read(), "Hello")

        stream <<< " World"
        try stream.close()

        XCTAssertEqual(read(), "Hello World")
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testBufferCorrectness", testBufferCorrectness),
        ("testStreamOperator", testStreamOperator),
        ("testJSONEncoding", testJSONEncoding),
        ("testFormattedOutput", testFormattedOutput),
        ("testLocalFileStream", testLocalFileStream),
    ]
}
