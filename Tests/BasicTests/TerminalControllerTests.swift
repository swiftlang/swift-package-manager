/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Basic
import libc

final class PseudoTerminal {
    let master: Int32
    let slave: Int32
    var outStream: LocalFileOutputByteStream

    init?(){
        var master: Int32 = 0
        var slave: Int32 = 0
        if openpty(&master, &slave, nil, nil, nil) != 0 {
            return nil
        }
        guard let outStream = try? LocalFileOutputByteStream(filePointer: fdopen(slave, "w")) else {
            return nil
        }
        self.outStream = outStream
        self.master = master
        self.slave = slave
    }

    func readMaster(maxChars n: Int = 1000) -> String? {
        var buf: [CChar] = [CChar](repeating: 0, count: n)
        if read(master, &buf, n) <= 0 {
            return nil
        }
        return String(cString: buf)
    }

    func close() {
        _ = libc.close(slave)
        _ = libc.close(master)
    }
}

final class TerminalControllerTests: XCTestCase {
    func testBasic() {
        guard let pty = PseudoTerminal(), let term = TerminalController(stream: pty.outStream) else {
            XCTFail("Couldn't create pseudo terminal.")
            return
        }

        // Test red color.
        term.write("hello", inColor: .red)
        XCTAssertEqual(pty.readMaster(), "\u{1B}[31mhello\u{1B}[0m")

        // Test clearLine.
        term.clearLine()
        XCTAssertEqual(pty.readMaster(), "\u{1B}[2K\r")

        // Test endline.
        term.endLine()
        XCTAssertEqual(pty.readMaster(), "\r\n")

        // Test move cursor.
        term.moveCursor(y: 3)
        XCTAssertEqual(pty.readMaster(), "\u{1B}[3A")

        // Test color wrapping.
        var wrapped = term.wrap("hello", inColor: .noColor)
        XCTAssertEqual(wrapped, "hello")

        wrapped = term.wrap("green", inColor: .green)
        XCTAssertEqual(wrapped, "\u{001B}[32mgreen\u{001B}[0m")
        pty.close()
    }

    static var allTests = [
        ("testBasic", testBasic),
    ]
}
