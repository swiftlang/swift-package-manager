/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
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

final class ProgressBarTests: XCTestCase {
    func testProgressBar() {
        guard let pty = PseudoTerminal() else {
            XCTFail("Couldn't create pseudo terminal.")
            return
        }

        // Test progress bar when writing to a non tty stream.
        let outStream = BufferedOutputByteStream()
        var bar = createProgressBar(forStream: outStream, header: "test")
        XCTAssertTrue(bar is SimpleProgressBar)

        runProgressBar(bar)
        XCTAssertEqual(outStream.bytes.asString, """
            test
            0%: 0
            1%: 1
            2%: 2
            3%: 3
            4%: 4
            5%: 5
            
            """)

        // Test progress bar when writing a tty stream.
        bar = createProgressBar(forStream: pty.outStream, header: "TestHeader")
        XCTAssertTrue(bar is ProgressBar)

        var output = ""
        let thread = Thread {
            while let out = pty.readMaster() {
                output += out
            }
        }
        thread.start()
        runProgressBar(bar)
        pty.closeSlave()
        // Make sure to read the complete output before checking it.
        thread.join()
        pty.closeMaster()
        XCTAssertTrue(output.spm_chuzzle()?.hasPrefix("\u{1B}[36m\u{1B}[1mTestHeader\u{1B}[0m") ?? false)
    }

    private func runProgressBar(_ bar: ProgressBarProtocol) {
        for i in 0...5 {
            bar.update(percent: i, text: String(i))
        }
        bar.complete(success: true)
    }
}
