/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Utility
import libc
@testable import Basic

typealias Thread = Basic.Thread

// FIXME: Copied from BasicTests, move to TestSupport once available.
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
        guard let outStream = try? LocalFileOutputByteStream(filePointer: fdopen(slave, "w"), closeOnDeinit: false) else {
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

    func closeSlave() {
        _ = libc.close(slave)
    }

    func closeMaster() {
        _ = libc.close(master)
    }
}

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
        XCTAssertEqual(outStream.bytes.asString, "test\n0%: 0\n1%: 1\n2%: 2\n3%: 3\n4%: 4\n5%: 5\n")

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
        XCTAssertTrue(output.chuzzle()?.hasPrefix("\u{1B}[36m\u{1B}[1mTestHeader\u{1B}[0m") ?? false)
    }

    private func runProgressBar(_ bar: ProgressBarProtocol) {
        for i in 0...5 {
            bar.update(percent: i, text: String(i))
        }
        bar.complete()
    }

    static var allTests = [
        ("testProgressBar", testProgressBar),
    ]
}
