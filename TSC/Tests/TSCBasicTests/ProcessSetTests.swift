/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import TSCBasic
import TSCLibc
import TSCUtility
import TSCTestSupport

class ProcessSetTests: XCTestCase {
    func script(_ name: String) -> String {
        return AbsolutePath(#file).parentDirectory.appending(components: "processInputs", name).pathString
    }

    func testSigInt() throws {
        try runProcessSetTest("blocking")
    }

    func testSigKillEscalation() throws {
        try runProcessSetTest("blocking-ignore-sigint", killTimeout: 0.1)
    }

    /// Helper method to run process set test.
    func runProcessSetTest(_ scriptName: String, killTimeout: Double = 2, file: StaticString = #file, line: UInt = #line) throws {

        // We launch the script in a separate thread and then call terminate method on the process set.
        // We expect that the process will be terminated via some signal (sigint or sigkill).

        let processSet = ProcessSet(killTimeout: killTimeout)
        let threadStartCondition = Condition()
        var processLaunched = false

        let t = Thread {
            do {
                // Launch the script and notify main thread.
                try withTemporaryFile { tempFile in
                    let waitFile = tempFile.path
                    let process = Process(args: self.script(scriptName), waitFile.pathString)
                    try processSet.add(process)
                    try process.launch()
                    guard waitForFile(waitFile) else {
                        XCTFail("Couldn't launch the process")
                        return
                    }
                    threadStartCondition.whileLocked {
                        processLaunched = true
                        threadStartCondition.signal()
                    }
                    let result = try process.waitUntilExit()
                    // Ensure we did termiated due to signal.
                    switch result.exitStatus {
                    case .signalled: break
                    default: XCTFail("Expected to exit via signal")
                    }
                }
            } catch {
                XCTFail("Error \(String(describing: error))")
            }
        }
        t.start()

        threadStartCondition.whileLocked {
            while !processLaunched {
                threadStartCondition.wait()
            }
        }
        processSet.terminate()

        t.join()
    }
}
