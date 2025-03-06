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

import Basics
import CoreCommands
import PackageModel

import func TSCBasic.exec
import enum TSCBasic.ProcessEnv

/// A card displaying a ``Snippet`` at the terminal.
struct SnippetCard: Card {
    enum Error: Swift.Error, CustomStringConvertible {
        case cantRunSnippet(reason: String)

        var description: String {
            switch self {
            case .cantRunSnippet(let reason):
                "Can't run snippet: \(reason)"
            }
        }
    }

    /// The snippet to display in the terminal.
    var snippet: Snippet

    /// The snippet's index within its group.
    var number: Int

    /// The tool used for eventually building and running a chosen snippet.
    var swiftCommandState: SwiftCommandState

    func render() -> String {
        let isColorized: Bool = self.swiftCommandState.options.logging.colorDiagnostics
        var rendered = isColorized ? colorized {
            brightYellow {
                "# "
                self.snippet.name
            }
            "\n\n"
        }.terminalString()
            :
            plain {
                plain {
                    "# "
                    self.snippet.name
                }
                "\n\n"
            }.terminalString()

        if !self.snippet.explanation.isEmpty {
            rendered += brightBlack {
                self.snippet.explanation
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "// " + $0 }
                    .joined(separator: "\n")
            }.terminalString()

            rendered += "\n\n"
        }

        rendered += self.snippet.presentationCode

        return rendered
    }

    var inputPrompt: String? {
        "\nRun this snippet? [R: run, or press Enter to return]"
    }

    func acceptLineInput(_ line: some StringProtocol) async -> CardEvent? {
        let trimmed = line.drop { $0.isWhitespace }.prefix { !$0.isWhitespace }.lowercased()
        guard !trimmed.isEmpty else {
            return .pop()
        }

        switch trimmed {
        case "r", "run":
            do {
                try await self.runExample()
            } catch {
                return .pop(SnippetCard.Error.cantRunSnippet(reason: error.localizedDescription))
            }
        case "c", "copy":
            print("Unimplemented")
        default:
            break
        }

        return .pop()
    }

    func runExample() async throws {
        print("Building '\(self.snippet.path)'\n")
        let buildSystem = try await swiftCommandState.createBuildSystem(
            explicitProduct: self.snippet.name,
            traitConfiguration: .init()
        )
        try await buildSystem.build(subset: .product(self.snippet.name))
        let executablePath = try swiftCommandState.productsBuildParameters.buildPath
            .appending(component: self.snippet.name)
        if let exampleTarget = try await buildSystem.getPackageGraph().module(for: snippet.name) {
            try ProcessEnv.chdir(exampleTarget.sources.paths[0].parentDirectory)
        }
        try exec(path: executablePath.pathString, args: [])
    }
}
