//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import XCTest
import Build

class SwiftCompilerOutputParserTests: XCTestCase {
    func testParse() throws {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(targetName: "dummy", delegate: delegate)

        parser.parse(bytes: """
            338
            {
              "kind": "began",
              "name": "compile",
              "inputs": [
                "test.swift"
              ],
              "outputs": [
                {
                  "type": "object",
                  "path": "/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test-77d991.o"
                }
              ],
              "pid": 22698,
              "command_executable": "swift",
              "command_arguments" : ["-frontend", "-c", "-primary-file", "test.swift"]
            }
            117
            {
              "kind": "finished",
              "name": "compile",
              "pid": 22698,
              "exit-status": 1,
              "output": "error: it failed :-("
            }
            233
            {
              "kind": "skipped",
              "name": "compile",
              "inputs": [
                "test2.swift"
              ],
              "outputs": [
                {
                  "type": "object",
                  "path": "/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test2-77d991.o"
                }
              ],
              "pid": 58776
            }
            250
            {
              "kind": "began",
              "name": "verify-module-interface",
              "inputs": [
                "main.swiftinterface"
              ],
              "pid": 31337,
              "command_executable": "swift",
              "command_arguments" : ["-frontend", "-typecheck-module-from-interface", "main.swiftinterface"]
            }
            299
            {
              "kind": "began",
              "name": "link",
              "inputs": [
                "/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test-77d991.o"
              ],
              "outputs": [
                {
                  "type": "image",
                  "path": "test"
                }
              ],
              "pid": 22699,
              "command_executable": "ld",
              "command_arguments" : ["-o", "option", "test"]
            }
            119
            {
              "kind": "signalled",
              "name": "link",
              "pid": 22699,
              "error-message": "Segmentation fault: 11",
              "signal": 4
            }

            """.utf8)

        delegate.assert(messages: [
            SwiftCompilerMessage(
                name: "compile",
                kind: .began(.init(
                    pid: 22698,
                    inputs: ["test.swift"],
                    outputs: [.init(
                        type: "object",
                        path: "/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test-77d991.o")],
                    commandExecutable: "swift",
                    commandArguments: ["-frontend", "-c", "-primary-file", "test.swift"]))),
            SwiftCompilerMessage(
                name: "compile",
                kind: .finished(.init(
                    pid: 22698,
                    output: "error: it failed :-("))),
            SwiftCompilerMessage(
                name: "compile",
                kind: .skipped(.init(
                    inputs: ["test2.swift"],
                    outputs: [.init(
                        type: "object",
                        path: "/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test2-77d991.o")]))),
            SwiftCompilerMessage(
                name: "verify-module-interface",
                kind: .began(.init(
                    pid: 31337,
                    inputs: ["main.swiftinterface"],
                    outputs: nil,
                    commandExecutable: "swift",
                    commandArguments: ["-frontend", "-typecheck-module-from-interface", "main.swiftinterface"]))),
            SwiftCompilerMessage(
                name: "link",
                kind: .began(.init(
                    pid: 22699,
                    inputs: ["/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test-77d991.o"],
                    outputs: [.init(
                        type: "image",
                        path: "test")],
                    commandExecutable: "ld",
                    commandArguments: ["-o", "option", "test"]))),
            SwiftCompilerMessage(
                name: "link",
                kind: .signalled(.init(
                    pid: 22699,
                    output: nil)))
        ], errorDescription: nil)
    }

    func testRawTextTransformsIntoUnknown() {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(targetName: "dummy", delegate: delegate)

        parser.parse(bytes: """
            2A

            """.utf8)
        delegate.assert(messages: [
            SwiftCompilerMessage(name: "unknown", kind: .unparsableOutput("2A\n"))
        ], errorDescription: nil)

        parser.parse(bytes: """
            119
            {
              "kind": "signalled",
              "name": "link",
              "pid": 22699,
              "error-message": "Segmentation fault: 11",
              "signal": 4
            }
            """.utf8)
        delegate.assert(messages: [
            SwiftCompilerMessage(name: "link", kind: .signalled(.init(pid: 22699, output: nil)))
        ], errorDescription: nil)
    }

    func testSignalledStopsParsing() {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(targetName: "dummy", delegate: delegate)

        parser.parse(bytes: """
            119
            {
              "kind": "signalled",
              "name": "link",
              "pid": 22699,
              "error-message": "Segmentation fault: 11",
              "signal": 4
            }
            """.utf8)
        delegate.assert(messages: [
            SwiftCompilerMessage(name: "link", kind: .signalled(.init(pid: 22699, output: nil)))
        ], errorDescription: nil)

        parser.parse(bytes: """

            117
            {
              "kind": "finished",
              "name": "compile",
              "pid": 22698,
              "exit-status": 1,
              "output": "error: it failed :-("
            }
            """.utf8)
        delegate.assert(messages: [], errorDescription: nil)
    }
}

class MockSwiftCompilerOutputParserDelegate: SwiftCompilerOutputParserDelegate {
    private var messages: [SwiftCompilerMessage] = []
    private var error: Error?

    func swiftCompilerOutputParser(_ parser: SwiftCompilerOutputParser, didParse message: SwiftCompilerMessage) {
        messages.append(message)
    }

    func swiftCompilerOutputParser(_ parser: SwiftCompilerOutputParser, didFailWith error: Error) {
        self.error = error
    }

    func assert(
        messages: [SwiftCompilerMessage],
        errorDescription: String?,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(messages, self.messages, file: file, line: line)
        let errorReason = (self.error as? LocalizedError)?.errorDescription ?? error?.localizedDescription
        XCTAssertEqual(errorDescription, errorReason, file: file, line: line)
        self.messages = []
        self.error = nil
    }
}
