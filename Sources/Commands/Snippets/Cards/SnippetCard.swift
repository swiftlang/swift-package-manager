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

import PackageModel
import TSCBasic

/// A card displaying a ``Snippet`` at the terminal.
struct SnippetCard: Card {
    enum Error: Swift.Error, CustomStringConvertible {
        case cantRunSnippet(reason: String)

        var description: String {
            switch self {
            case let .cantRunSnippet(reason):
                return "Can't run snippet: \(reason)"
            }
        }
    }
    /// The snippet to display in the terminal.
    var snippet: Snippet

    /// The snippet's index within its group.
    var number: Int

    /// The tool used for eventually building and running a chosen snippet.
    var swiftTool: SwiftTool

    func render() -> String {
        var rendered = colorized {
            brightYellow {
                "# "
                snippet.name
            }
            "\n\n"
        }.terminalString()

        if !snippet.explanation.isEmpty {
            rendered += brightBlack {
                snippet.explanation
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "// " + $0 }
                .joined(separator: "\n")
            }.terminalString()

            rendered += "\n\n"
        }

        rendered += snippet.presentationCode

        return rendered
    }

    var inputPrompt: String? {
        return "\nRun this snippet? [R: run, or press Enter to return]"
    }

    func acceptLineInput<S>(_ line: S) -> CardEvent? where S : StringProtocol {
        let trimmed = line.drop { $0.isWhitespace }.prefix { !$0.isWhitespace }.lowercased()
        guard !trimmed.isEmpty else {
            return .pop()
        }

        switch trimmed {
        case "r", "run":
            do {
                try runExample()
            } catch {
                return .pop(SnippetCard.Error.cantRunSnippet(reason: error.localizedDescription))
            }
            break
        case "c", "copy":
            print("Unimplemented")
            break
        default:
            break
        }

        return .pop()
    }

    func runExample() throws {
        print("Building '\(snippet.path)'\n")
        let buildSystem = try swiftTool.createBuildSystem(explicitProduct: snippet.name)
        try buildSystem.build(subset: .product(snippet.name))
        let executablePath = try swiftTool.buildParameters().buildPath.appending(component: snippet.name)
        if let exampleTarget = try buildSystem.getPackageGraph().allTargets.first(where: { $0.name == snippet.name }) {
            try ProcessEnv.chdir(exampleTarget.sources.paths[0].parentDirectory)
        }
        try exec(path: executablePath.pathString, args: [])
    }
}
