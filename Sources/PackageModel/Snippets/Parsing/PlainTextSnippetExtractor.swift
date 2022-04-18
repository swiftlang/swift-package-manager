//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

fileprivate enum SnippetVisibility {
    case shown
    case hidden
}

fileprivate extension StringProtocol {
    /// If the string is a line comment, attempt to parse
    /// a ``SnippetVisibility`` with `mark: show` or `mark: hide`.
    var parsedVisibilityMark: SnippetVisibility? {
        guard var comment = parsedLineCommentText else {
            return nil
        }

        comment = comment.drop { $0.isWhitespace }

        if comment.lowercased().starts(with: "mark: show") {
            return SnippetVisibility.shown
        } else if comment.lowercased().starts(with: "mark: hide") {
            return SnippetVisibility.hidden
        } else {
            return nil
        }
    }

    /// If the string is a line comment starting with `"//"`, return the
    /// contents with the comment marker stripped.
    var parsedLineCommentText: Self.SubSequence? {
        var trimmed = self.drop { $0.isWhitespace }
        guard trimmed.starts(with: "//") else {
            return nil
        }
        trimmed.removeFirst(2)
        return trimmed
    }

    var isEmptyOrWhiteSpace: Bool {
        return self.isEmpty || self.allSatisfy { $0.isWhitespace }
    }
}

fileprivate extension String {
    mutating func removeLeadingAndTrailingNewlines() {
        while self.starts(with: "\n") {
            self.removeFirst(1)
        }
        while self.suffix(1) == "\n" {
            self.removeLast(1)
        }
    }

    /// Returns a re-indented string with the most indentation removed
    /// without changing the relative indentation between lines. This is
    /// useful for re-indenting some inner part of a block of nested code.
    mutating func trimExtraIndentation() {
        var lines = self.split(separator: "\n", maxSplits: Int.max,
                               omittingEmptySubsequences: false)
        lines = Array(lines
                        .drop(while: { $0.isEmptyOrWhiteSpace })
                        .reversed()
                        .drop(while: { $0.isEmptyOrWhiteSpace })
                        .reversed())

        let minimumIndentation = lines.map {
            guard !$0.isEmpty else {
                return Int.max
            }
            return $0.prefix { $0 == " " }.count
        }.min() ?? 0

        guard minimumIndentation > 0 else {
            return
        }

        self = lines.map { $0.dropFirst(minimumIndentation) }
            .joined(separator: "\n")
    }
}

/// Extracts a ``Snippet`` structure from Swift source code.
///
/// - todo: In order to support different styles of comments, it might be
///   better to adopt SwiftSyntax if possible in the future.
struct PlainTextSnippetExtractor {
    var source: String
    var explanation = ""
    var presentationCode = ""
    private var currentVisibility = SnippetVisibility.shown

    init(source: String) {
        self.source = source
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)

        var lastExplanationLine = "..."
        var lastPresentationCodeLine = "..."

        for line in lines {
            if let visibility = line.parsedVisibilityMark {
                self.currentVisibility = visibility
                continue
            }

            guard case .shown = currentVisibility else {
                continue
            }

            if var comment = line.parsedLineCommentText,
               comment.starts(with: "!") {
                comment.removeFirst(1)
                comment = comment.drop { $0.isWhitespace }
                if lastExplanationLine.isEmptyOrWhiteSpace && comment.isEmptyOrWhiteSpace {
                    continue
                }
                print(comment, to: &explanation)
                lastExplanationLine = String(comment)
            } else {
                if lastPresentationCodeLine.isEmptyOrWhiteSpace && line.isEmptyOrWhiteSpace {
                    continue
                }
                print(line, to: &presentationCode)
                lastPresentationCodeLine = String(line)
            }
        }
        self.explanation
            .removeLeadingAndTrailingNewlines()

        self.presentationCode
            .removeLeadingAndTrailingNewlines()
        
        self.presentationCode
            .trimExtraIndentation()
    }
}
