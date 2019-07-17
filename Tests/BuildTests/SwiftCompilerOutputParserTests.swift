/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
@testable import SPMBuild

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

class SwiftCompilerOutputParserTests: XCTestCase {
    func testParse() throws {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(targetName: "dummy", delegate: delegate)

        parser.parse(bytes: "33".utf8)
        delegate.assert(messages: [], errorDescription: nil)

        parser.parse(bytes: "".utf8)
        delegate.assert(messages: [], errorDescription: nil)

        parser.parse(bytes: """
            8
            {
              "kind": "began",
              "name": "compile",
              "inputs": [
                "test.swift"
              ],

            """.utf8)
        delegate.assert(messages: [], errorDescription: nil)

        parser.parse(bytes: "".utf8)
        delegate.assert(messages: [], errorDescription: nil)

        parser.parse(bytes: """
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
                    commandArguments: ["-frontend", "-c", "-primary-file", "test.swift"])))
        ], errorDescription: nil)

        parser.parse(bytes: """
            {
              "kind": "finished",
              "name": "compile",
              "pid": 22698,
              "exit-status": 1,
              "output": "error: it failed :-("
            }
            """.utf8)
        delegate.assert(messages: [
            SwiftCompilerMessage(
                name: "compile",
                kind: .finished(.init(
                    pid: 22698,
                    output: "error: it failed :-(")))
        ], errorDescription: nil)

        parser.parse(bytes: """

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
            """.utf8)
        delegate.assert(messages: [
            SwiftCompilerMessage(
                name: "compile",
                kind: .skipped(.init(
                    inputs: ["test2.swift"],
                    outputs: [.init(
                        type: "object",
                        path: "/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test2-77d991.o")]))),
            SwiftCompilerMessage(
                name: "link",
                kind: .began(.init(
                    pid: 22699,
                    inputs: ["/var/folders/yc/rgflx8m11p5d71k1ydy0l_pr0000gn/T/test-77d991.o"],
                    outputs: [.init(
                        type: "image",
                        path: "test")],
                    commandExecutable: "ld",
                    commandArguments: ["-o", "option", "test"])))
        ], errorDescription: nil)

        parser.parse(bytes: """

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
                name: "link",
                kind: .signalled(.init(
                    pid: 22699,
                    output: nil)))
        ], errorDescription: nil)
    }

    func testInvalidMessageSizeBytes() {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(targetName: "dummy", delegate: delegate)

        parser.parse(bytes: [65, 66, 200, 67, UInt8(ascii: "\n")])
        delegate.assert(messages: [], errorDescription: "invalid UTF8 bytes")

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
        delegate.assert(messages: [], errorDescription: nil)
    }

    func testInvalidMessageSizeValue() {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(targetName: "dummy", delegate: delegate)

        parser.parse(bytes: """
            2A

            """.utf8)
        delegate.assert(messages: [
            SwiftCompilerMessage(name: "unknown", kind: .unparsableOutput("2A"))
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

    func testInvalidMessageBytes() {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(targetName: "dummy", delegate: delegate)

        parser.parse(bytes: """
            4

            """.utf8)
        delegate.assert(messages: [], errorDescription: nil)
        parser.parse(bytes: [65, 66, 200, 67, UInt8(ascii: "\n")])
        delegate.assert(messages: [], errorDescription: "unexpected JSON message")

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
        delegate.assert(messages: [], errorDescription: nil)
    }

    func testInvalidMessageMissingField() {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(targetName: "dummy", delegate: delegate)

        parser.parse(bytes: """
            23
            {
              "invalid": "json"
            }
            """.utf8)
        delegate.assert(messages: [], errorDescription: "unexpected JSON message")

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
        delegate.assert(messages: [], errorDescription: nil)
    }

    func testInvalidMessageInvalidValue() {
        let delegate = MockSwiftCompilerOutputParserDelegate()
        let parser = SwiftCompilerOutputParser(targetName: "dummy", delegate: delegate)

        parser.parse(bytes: """
            23
            {
              "kind": "invalid",
              "name": "link",
              "pid": 22699,
              "error-message": "Segmentation fault: 11",
              "signal": 4
            }
            """.utf8)
        delegate.assert(messages: [], errorDescription: "unexpected JSON message")

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
        delegate.assert(messages: [], errorDescription: nil)
    }
}
