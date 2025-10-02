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
import TSCUtility

/// A card showing the snippets in a ``SnippetGroup``.
struct SnippetGroupCard: Card {
    /// The snippet group to display in the terminal.
    var snippetGroup: SnippetGroup

    /// The tool used for eventually building and running a chosen snippet.
    var swiftCommandState: SwiftCommandState

    var inputPrompt: String? {
        return """

            Choose a number or a name from the list of snippets.
            To go back, press enter.
            To exit, enter `q`.
            """
    }

    func acceptLineInput<S>(_ line: S) -> CardEvent? where S : StringProtocol {
        if line.isEmpty || line.allSatisfy({ $0.isWhitespace }) {
            return .pop()
        }
        if line.prefix(while: { !$0.isWhitespace }).lowercased() == "q" {
            return .quit()
        }
        if let index = Int(line),
           snippetGroup.snippets.indices.contains(index) {
            return .push(SnippetCard(snippet: snippetGroup.snippets[index], number: index, swiftCommandState: swiftCommandState))
        } else if let foundSnippetIndex = snippetGroup.snippets.firstIndex(where: { $0.name == line }) {
            return .push(SnippetCard(snippet: snippetGroup.snippets[foundSnippetIndex], number: foundSnippetIndex, swiftCommandState: swiftCommandState))
        } else {
            print(red { "There is not a snippet by that name or index." })
            return nil
        }
    }

    func render() -> String {
        let isColorized = swiftCommandState.options.logging.colorDiagnostics
        precondition(!snippetGroup.snippets.isEmpty)

        var rendered = isColorized ? brightYellow {
            """
            # \(snippetGroup.name)


            """
        }.terminalString() :
            plain {
                """
                # \(snippetGroup.name)


                """
            }.terminalString()

        if !snippetGroup.explanation.isEmpty {
            rendered += snippetGroup.explanation
        }

        rendered += "\n"
        rendered += snippetGroup.snippets
            .enumerated()
            .map { pair -> String in
                let (number, snippet) = pair
                return isColorized ? brightCyan {
                    "\(number). \(snippet.name)\n"
                    plain {
                        snippet.explanation.spm_multilineIndent(count: 3)
                    }
                }.terminalString() :
                    plain {
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
