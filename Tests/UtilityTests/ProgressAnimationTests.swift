/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Utility
import SPMLibc
import TestSupport
@testable import Basic

typealias Thread = Basic.Thread

final class ProgressAnimationTests: XCTestCase {
    func testPercentProgressAnimation() {
        guard let pty = PseudoTerminal() else {
            XCTFail("Couldn't create pseudo terminal.")
            return
        }

        // Test progress animaton when writing to a non tty stream.
        let outStream = BufferedOutputByteStream()
        var animation = PercentProgressAnimation(stream: outStream, header: "test")

        runProgressAnimation(animation)
        XCTAssertEqual(outStream.bytes.asString, """
            test
            0%: 0
            10%: 1
            20%: 2
            30%: 3
            40%: 4
            50%: 5
            
            """)

        // Test progress bar when writing a tty stream.
        animation = PercentProgressAnimation(stream: pty.outStream, header: "TestHeader")

        var output = ""
        let thread = Thread {
            while let out = pty.readMaster() {
                output += out
            }
        }
        thread.start()
        runProgressAnimation(animation)
        pty.closeSlave()
        // Make sure to read the complete output before checking it.
        thread.join()
        pty.closeMaster()
        XCTAssertTrue(output.spm_chuzzle()?.hasPrefix("\u{1B}[36m\u{1B}[1mTestHeader\u{1B}[0m") ?? false)
    }

    func testNinjaProgressAnimation() {
        guard let pty = PseudoTerminal() else {
            XCTFail("Couldn't create pseudo terminal.")
            return
        }

        // Test progress animaton when writing to a non tty stream.
        let outStream = BufferedOutputByteStream()
        var animation = NinjaProgressAnimation(stream: outStream)

        runProgressAnimation(animation)
        XCTAssertEqual(outStream.bytes.asString, """
            [0/10] 0
            [1/10] 1
            [2/10] 2
            [3/10] 3
            [4/10] 4
            [5/10] 5

            """)

        // Test progress bar when writing a tty stream.
        animation = NinjaProgressAnimation(stream: pty.outStream)

        var output = ""
        let thread = Thread {
            while let out = pty.readMaster() {
                output += out
            }
        }
        thread.start()
        runProgressAnimation(animation)
        pty.closeSlave()
        // Make sure to read the complete output before checking it.
        thread.join()
        pty.closeMaster()
        XCTAssertEqual(output.spm_chuzzle(), """
            \u{1B}[2K\r[0/10] 0\
            \u{1B}[2K\r[1/10] 1\
            \u{1B}[2K\r[2/10] 2\
            \u{1B}[2K\r[3/10] 3\
            \u{1B}[2K\r[4/10] 4\
            \u{1B}[2K\r[5/10] 5
            """)
    }

    private func runProgressAnimation(_ animation: ProgressAnimationProtocol) {
        for i in 0...5 {
            animation.update(step: i, total: 10, text: String(i))
        }
        animation.complete(success: true)
    }
}
