/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCTestSupport
import TSCLibc
import TSCBasic

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
        term.moveCursor(up: 3)
        XCTAssertEqual(pty.readMaster(), "\u{1B}[3A")

        // Test color wrapping.
        var wrapped = term.wrap("hello", inColor: .noColor)
        XCTAssertEqual(wrapped, "hello")

        wrapped = term.wrap("green", inColor: .green)
        XCTAssertEqual(wrapped, "\u{001B}[32mgreen\u{001B}[0m")
        pty.close()
    }
}
