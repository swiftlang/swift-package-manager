/*
This source file is part of the Swift.org open source project

Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import TSCTestSupport
import XCTest

class StringChecker {
    private let string: String
    private let lines: [Substring]
    private var currentLineIndex: Int
    private var currentLine: Substring { lines[currentLineIndex] }

    init(string: String) {
        self.string = string
        self.lines = string.split(separator: "\n")
        self.currentLineIndex = 0
    }

    func check(_ pattern: StringPattern, file: StaticString = #file, line: UInt = #line) {
        while let line = nextLine() {
            if pattern ~= line {
                return
            }
        }

        XCTFail(string, file: file, line: line)
    }

    func checkNext(_ pattern: StringPattern, file: StaticString = #file, line: UInt = #line) {
        if let line = nextLine(), pattern ~= line {
            return
        }

        XCTFail(string, file: file, line: line)
    }

    private func nextLine() -> String? {
        guard currentLineIndex < lines.count else {
            return nil
        }

        let currentLine = lines[currentLineIndex]
        currentLineIndex += 1
        return String(currentLine)
    }
}

func XCTAssertContents(
    _ string: String,
    _ check: (StringChecker) -> Void
) {
    let checker = StringChecker(string: string)
    check(checker)
}
