//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftParser

extension ProductDescription: ManifestSyntaxRepresentable {
    /// The function name in the package manifest.
    ///
    /// Some of these are actually invalid, but it's up to the caller
    /// to check the precondition.
    private var functionName: String {
        switch type {
        case .executable: "executable"
        case .library(_): "library"
        case .macro: "macro"
        case .plugin: "plugin"
        case .snippet: "snippet"
        case .test: "test"
        }
    }

    func asSyntax() -> ExprSyntax {
        var arguments: [LabeledExprSyntax] = []
        arguments.append(label: "name", stringLiteral: name)

        // Libraries have a type.
        if case .library(let libraryType) = type {
            switch libraryType {
            case .automatic:
                break

            case .dynamic, .static:
                arguments.append(
                    label: "type",
                    expression: ".\(raw: libraryType.rawValue)"
                )
            }
        }

        arguments.appendIfNonEmpty(
            label: "targets",
            arrayLiteral: targets
        )

        let separateParen: String = arguments.count > 1 ? "\n" : ""
        let argumentsSyntax = LabeledExprListSyntax(arguments)
        return ".\(raw: functionName)(\(argumentsSyntax)\(raw: separateParen))"
    }
}
