/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TSCBasic

class OutputByteStreamTests: XCTestCase {
    func testBasics() {
        var stream = BufferedOutputByteStream()
        
        "Hel".write(to: stream)
        "Hello".dropFirst(3).write(to: stream)
        Character(",").write(to: stream)
        Character(" ").write(to: stream)
        [UInt8]("wor".utf8).write(to: stream)
        [UInt8]("world".utf8)[3..<5].write(to: stream)
        
        let streamable: TextOutputStreamable = Character("!")
        streamable.write(to: &stream)
        
        XCTAssertEqual(stream.position, "Hello, world!".utf8.count)
        stream.flush()
        XCTAssertEqual(stream.bytes, "Hello, world!")
    }
    
    func testStreamOperator() {
        let stream = BufferedOutputByteStream()

        stream <<< "Hello" <<< Character(",") <<< Character(" ") <<< [UInt8]("wor".utf8) <<< [UInt8]("world".utf8)[3..<5]
        
        XCTAssertEqual(stream.position, "Hello, world".utf8.count)
        XCTAssertEqual(stream.bytes, "Hello, world")
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

        do {
            var stream = BufferedOutputByteStream()
            stream <<< Format.asRepeating(string: "foo", count: 1)
            XCTAssertEqual(stream.bytes, "foo")

            stream = BufferedOutputByteStream()
            stream <<< Format.asRepeating(string: "foo", count: 0)
            XCTAssertEqual(stream.bytes, "")

            stream = BufferedOutputByteStream()
            stream <<< Format.asRepeating(string: "x", count: 4)
            XCTAssertEqual(stream.bytes, "xxxx")

            stream = BufferedOutputByteStream()
            stream <<< Format.asRepeating(string: "foo", count: 3)
            XCTAssertEqual(stream.bytes, "foofoofoo")
        }
    }

    func testLocalFileStream() throws {
        try withTemporaryFile { tempFile in

            func read() -> String? {
                return try! localFileSystem.readFileContents(tempFile.path).validDescription
            }

            let stream = try LocalFileOutputByteStream(tempFile.path)
            stream <<< "Hello"
            stream.flush()
            XCTAssertEqual(read(), "Hello")

            stream <<< " World"
            try stream.close()

            XCTAssertEqual(read(), "Hello World")
        }
    }

    func testLocalFileStreamArraySliceUnbuffered() throws {
        try withTemporaryFile { tempFile in
            let bytes1k = [UInt8](repeating: 0, count: 1 << 10)

            func read() -> ByteString? {
                return try! localFileSystem.readFileContents(tempFile.path)
            }

            let stream = try LocalFileOutputByteStream(tempFile.path, buffered: false)
            stream.write(bytes1k)
            stream.flush()
            XCTAssertEqual(read()!.contents, bytes1k)
            try stream.close()
        }
    }

    func testThreadSafeStream() {
        var threads = [Thread]()

        let stream = BufferedOutputByteStream()
        let threadSafeStream = ThreadSafeOutputByteStream(stream)

        let t1 = Thread {
            for _ in 0..<1000 {
                threadSafeStream <<< "Hello"
            }
        }
        threads.append(t1)

        let t2 = Thread {
            for _ in 0..<1000 {
                threadSafeStream.write("Hello")
            }
        }
        threads.append(t2)

        threads.forEach { $0.start() }
        threads.forEach { $0.join() }

        XCTAssertEqual(stream.bytes.count, 5 * 2000)
    }
}
