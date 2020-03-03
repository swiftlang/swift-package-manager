/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import TSCTestSupport
import TSCUtility

class JSONMessageStreamingParserTests: XCTestCase {
    func testParse() throws {
        let delegate = MockParserDelegate()
        let parser = JSONMessageStreamingParser(delegate: delegate)

        parser.parse(bytes: "7".utf8)
        delegate.assert(messages: [], rawTexts: [], errorDescription: nil)

        parser.parse(bytes: "".utf8)
        delegate.assert(messages: [], rawTexts: [], errorDescription: nil)

        parser.parse(bytes: """
            3
            {
              "id": 123456,
              "type": "error",

            """.utf8)
        delegate.assert(messages: [], rawTexts: [], errorDescription: nil)

        parser.parse(bytes: "".utf8)
        delegate.assert(messages: [], rawTexts: [], errorDescription: nil)

        parser.parse(bytes: """
              "message": "This is outrageous!"
            }
            78

            """.utf8)
        delegate.assert(
            messages: [MockParserDelegate.Message(id: 123456, type: "error", message: "This is outrageous!")],
            rawTexts: [],
            errorDescription: nil
        )

        parser.parse(bytes: """
            {
              "id": 456798,
              "type": "warning",
              "message": "You should be careful."
            }
            """.utf8)
            delegate.assert(
                messages: [MockParserDelegate.Message(id: 456798, type: "warning", message: "You should be careful.")],
                rawTexts: [],
                errorDescription: nil
            )

        parser.parse(bytes: """

            76
            {
              "id": 789123,
              "type": "note",
              "message": "Note to self: buy milk."
            }
            64
            {
              "id": 456123,
              "type": "note",
              "message": "...and eggs"
            }
            63
            """.utf8)
        delegate.assert(
            messages: [
                MockParserDelegate.Message(id: 789123, type: "note", message: "Note to self: buy milk."),
                MockParserDelegate.Message(id: 456123, type: "note", message: "...and eggs"),
            ],
            rawTexts: [],
            errorDescription: nil
        )

        parser.parse(bytes: """

            {
              "id": 753869,
              "type": "error",
              "message": "Pancakes!"
            }

            """.utf8)
        delegate.assert(
            messages: [
                MockParserDelegate.Message(id: 753869, type: "error", message: "Pancakes!"),
            ],
            rawTexts: [],
            errorDescription: nil
        )
    }

    func testInvalidMessageSizeBytes() {
        let delegate = MockParserDelegate()
        let parser = JSONMessageStreamingParser(delegate: delegate)

        parser.parse(bytes: [65, 66, 200, 67, UInt8(ascii: "\n")])
        delegate.assert(messages: [], rawTexts: [], errorDescription: "invalid UTF8 bytes")

        parser.parse(bytes: """
            76
            {
              "id": 789123,
              "type": "note",
              "message": "Note to self: buy milk."
            }
            """.utf8)
        delegate.assert(messages: [], rawTexts: [], errorDescription: nil)
    }

    func testInvalidMessageSizeValue() {
        let delegate = MockParserDelegate()
        let parser = JSONMessageStreamingParser(delegate: delegate)

        parser.parse(bytes: """
            2A

            """.utf8)
        delegate.assert(messages: [], rawTexts: ["2A"], errorDescription: nil)

        parser.parse(bytes: """
            76
            {
              "id": 789123,
              "type": "note",
              "message": "Note to self: buy milk."
            }
            """.utf8)
        delegate.assert(
            messages: [MockParserDelegate.Message(id: 789123, type: "note", message: "Note to self: buy milk.")],
            rawTexts: [],
            errorDescription: nil
        )
    }

    func testInvalidMessageBytes() {
        let delegate = MockParserDelegate()
        let parser = JSONMessageStreamingParser(delegate: delegate)

        parser.parse(bytes: """
            4

            """.utf8)
        delegate.assert(messages: [], rawTexts: [], errorDescription: nil)
        parser.parse(bytes: [65, 66, 200, 67, UInt8(ascii: "\n")])
        delegate.assert(messages: [], rawTexts: [], errorDescription: .contains("unexpected JSON message"))

        parser.parse(bytes: """
            76
            {
              "id": 789123,
              "type": "note",
              "message": "Note to self: buy milk."
            }
            """.utf8)
        delegate.assert(messages: [], rawTexts: [], errorDescription: nil)
    }

    func testInvalidMessageMissingField() {
        let delegate = MockParserDelegate()
        let parser = JSONMessageStreamingParser(delegate: delegate)

        parser.parse(bytes: """
            23
            {
              "invalid": "json"
            }
            """.utf8)
        delegate.assert(messages: [], rawTexts: [], errorDescription: .contains("unexpected JSON message"))

        parser.parse(bytes: """
            76
            {
              "id": 789123,
              "type": "note",
              "message": "Note to self: buy milk."
            }
            """.utf8)
        delegate.assert(messages: [], rawTexts: [], errorDescription: nil)
    }

    func testInvalidMessageInvalidValue() {
        let delegate = MockParserDelegate()
        let parser = JSONMessageStreamingParser(delegate: delegate)

        parser.parse(bytes: """
            5
            {
              "id": 789123,
              "type": "note",
              "message": "Note to self: buy milk."
            }
            """.utf8)
        delegate.assert(messages: [], rawTexts: [], errorDescription: .contains("unexpected JSON message"))

        parser.parse(bytes: """
            76
            {
              "id": 789123,
              "type": "note",
              "message": "Note to self: buy milk."
            }
            """.utf8)
        delegate.assert(messages: [], rawTexts: [], errorDescription: nil)
    }
}

private final class MockParserDelegate: JSONMessageStreamingParserDelegate {
    struct Message: Equatable, Decodable {
        let id: Int
        let type: String
        let message: String
    }

    private var messages: [Message] = []
    private var rawTexts: [String] = []
    private var error: Error? = nil

    func jsonMessageStreamingParser(
        _ parser: JSONMessageStreamingParser<MockParserDelegate>,
        didParse message: Message
    ) {
        messages.append(message)
    }

    func jsonMessageStreamingParser(
        _ parser: JSONMessageStreamingParser<MockParserDelegate>,
        didParseRawText text: String
    ) {
        rawTexts.append(text)
    }

    func jsonMessageStreamingParser(
        _ parser: JSONMessageStreamingParser<MockParserDelegate>,
        didFailWith error: Error
    ) {
        self.error = error
    }

    func assert(
        messages: [Message],
        rawTexts: [String],
        errorDescription: StringPattern?,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(messages, self.messages, file: file, line: line)
        XCTAssertEqual(rawTexts, self.rawTexts, file: file, line: line)

        let errorReason = (self.error as? LocalizedError)?.errorDescription ?? error?.localizedDescription
        switch (errorReason, errorDescription) {
        case (let errorReason?, let errorDescription?):
            XCTAssertMatch(errorReason, errorDescription, file: file, line: line)
        case (nil, nil):
            break
        case (let errorReason?, nil):
            XCTFail("unexpected error: \(errorReason)")
        case (nil, .some):
            XCTFail("unexpected success")
        }

        self.messages.removeAll()
        self.rawTexts.removeAll()
        self.error = nil
    }
}
