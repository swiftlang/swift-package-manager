/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCUtility
import TSCLibc
import TSCTestSupport
import TSCBasic

typealias Thread = TSCBasic.Thread

final class ProgressAnimationTests: XCTestCase {
    func testPercentProgressAnimationDumbTerminal() {
        var outStream = BufferedOutputByteStream()
        var animation = PercentProgressAnimation(stream: outStream, header: "TestHeader")

        runProgressAnimation(animation)
        XCTAssertEqual(outStream.bytes.validDescription, """
            TestHeader
            0%: 0
            10%: 1
            20%: 2
            30%: 3
            40%: 4
            50%: 5

            """)

        outStream = BufferedOutputByteStream()
        animation = PercentProgressAnimation(stream: outStream, header: "TestHeader")

        animation.complete(success: true)
        XCTAssertEqual(outStream.bytes.validDescription, "")
    }

    func testPercentProgressAnimationTTY() throws {
        let output = try readingTTY { tty in
            let animation = PercentProgressAnimation(stream: tty.outStream, header: "TestHeader")
            runProgressAnimation(animation)
        }

        let startCyan = "\u{1B}[36m"
        let bold = "\u{1B}[1m"
        let end = "\u{1B}[0m"
        XCTAssertMatch(output.spm_chuzzle(), .prefix("\(startCyan)\(bold)TestHeader\(end)"))
    }

    func testNinjaProgressAnimationDumbTerminal() {
        var outStream = BufferedOutputByteStream()
        var animation = NinjaProgressAnimation(stream: outStream)

        runProgressAnimation(animation)
        XCTAssertEqual(outStream.bytes.validDescription, """
            [0/10] 0
            [1/10] 1
            [2/10] 2
            [3/10] 3
            [4/10] 4
            [5/10] 5

            """)

        outStream = BufferedOutputByteStream()
        animation = NinjaProgressAnimation(stream: outStream)

        animation.complete(success: true)
        XCTAssertEqual(outStream.bytes.validDescription, "")
    }

    func testNinjaProgressAnimationTTY() throws {
        var output = try readingTTY { tty in
            let animation = NinjaProgressAnimation(stream: tty.outStream)
            runProgressAnimation(animation)
        }

        let clearLine = "\u{1B}[2K\r"
        let newline = "\r\n"
        XCTAssertEqual(output, """
            \(clearLine)[0/10] 0\
            \(clearLine)[1/10] 1\
            \(clearLine)[2/10] 2\
            \(clearLine)[3/10] 3\
            \(clearLine)[4/10] 4\
            \(clearLine)[5/10] 5\(newline)
            """)

        output = try readingTTY { tty in
            let animation = NinjaProgressAnimation(stream: tty.outStream)
            animation.complete(success: true)
        }

        XCTAssertEqual(output, "")
    }

    private func readingTTY(_ closure: (PseudoTerminal) -> Void) throws -> String {
        guard let terminal = PseudoTerminal() else {
            struct PseudoTerminalCreationError: Error {}
            throw PseudoTerminalCreationError()
        }

        var output = ""
        let thread = Thread {
            while let out = terminal.readMaster() {
                output += out
            }
        }

        thread.start()
        closure(terminal)
        terminal.closeSlave()

        // Make sure to read the complete output before checking it.
        thread.join()
        terminal.closeMaster()

        return output
    }

    private func runProgressAnimation(_ animation: ProgressAnimationProtocol) {
        for i in 0...5 {
            animation.update(step: i, total: 10, text: String(i))
        }

        animation.complete(success: true)
    }
}
