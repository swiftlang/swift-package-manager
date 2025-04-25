/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import TSCTestSupport
public class StringChecker {
    private let string: String
    private let lines: [Substring]
    private var currentLineIndex: Int
    private var currentLine: Substring { self.lines[self.currentLineIndex] }

    public init(string: String) {
        self.string = string
        self.lines = string.split(separator: ProcessInfo.EOL)
        self.currentLineIndex = 0
    }

    public func check(_ pattern: StringPattern, file: StaticString = #file, line: UInt = #line) -> Bool {
        while let line = nextLine() {
            if pattern ~= line {
                return true
            }
        }
        return false
    }

    public func checkNext(_ pattern: StringPattern, file: StaticString = #file, line: UInt = #line) -> Bool {
        if let line = nextLine(), pattern ~= line {
            return true
        }

        return false
    }

    private func nextLine() -> String? {
        guard self.currentLineIndex < self.lines.count else {
            return nil
        }

        let currentLine = self.lines[self.currentLineIndex]
        self.currentLineIndex += 1
        return String(currentLine)
    }
}
