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

import CoreCommands
import PackageModel

/// A card showing the snippets in a ``SnippetGroup``.
struct SnippetGroupCard: Card {
    /// The snippet group to display in the terminal.
    var snippetGroup: SnippetGroup

    /// The tool used for eventually building and running a chosen snippet.
    var swiftCommandState: SwiftCommandState

    var inputPrompt: String? {
        """

        Choose a number or a name from the list of snippets.
        To go back, press enter.
        To exit, enter `q`.
        """
    }

    func acceptLineInput(_ line: some StringProtocol) -> CardEvent? {
        if line.isEmpty || line.allSatisfy(\.isWhitespace) {
            return .pop()
        }
        if line.prefix(while: { !$0.isWhitespace }).lowercased() == "q" {
            return .quit()
        }
        if let index = Int(line),
           snippetGroup.snippets.indices.contains(index)
        {
            return .push(SnippetCard(
                snippet: self.snippetGroup.snippets[index],
                number: index,
                swiftCommandState: self.swiftCommandState
            ))
        } else if let foundSnippetIndex = snippetGroup.snippets.firstIndex(where: { $0.name == line }) {
            return .push(SnippetCard(
                snippet: self.snippetGroup.snippets[foundSnippetIndex],
                number: foundSnippetIndex,
                swiftCommandState: self.swiftCommandState
            ))
        } else {
            print(red { "There is not a snippet by that name or index." })
            return nil
        }
    }

    func render() -> String {
        let isColorized = self.swiftCommandState.options.logging.colorDiagnostics
        precondition(!self.snippetGroup.snippets.isEmpty)

        var rendered = isColorized ? brightYellow {
            """
            # \(self.snippetGroup.name)


            """
        }.terminalString() :
            plain {
                """
                # \(self.snippetGroup.name)


                """
            }.terminalString()

        if !self.snippetGroup.explanation.isEmpty {
            rendered += self.snippetGroup.explanation
        }

        rendered += "\n"
        rendered += self.snippetGroup.snippets
            .enumerated()
            .map { pair -> String in
                let (number, snippet) = pair
                return isColorized ? brightCyan {
                    "\(number). \(snippet.name)\n"
                    plain {
                        snippet.explanation.spm_multilineIndent(count: 3)
                    }
                }.terminalString() :
                    brightCyan {
                        "\(number). \(snippet.name)\n"
                        plain {
                            snippet.explanation.spm_multilineIndent(count: 3)
                        }
                    }.terminalString()
            }
            .joined(separator: "\n\n")

        return rendered
    }
}
