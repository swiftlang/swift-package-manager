//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftDiagnostics
import SwiftSyntax

/// A description of a limitation of the manifest parser, such as an
/// unrecognized syntax node or some kind of dynamic expression that the
/// manifest parser does not understand.
///
/// Every limitation will have a corresponding syntax node and can be
/// treated as a `DiagnosticMessage` so that it can be shown to the user.
public enum ManifestParseLimitation {
    /// An nexpected syntax node of any kind.
    case unexpectedSyntax(Syntax)

    /// An import declaration that refers to an unknown module.
    case unknownImportModule(ImportDeclSyntax, moduleName: String)

    /// An import declaration that uses unsupported declaration syntax.
    case unsupportedImportForm(ImportDeclSyntax)

    /// A variable declaration that doesn't follow the straightforward
    /// "let x = y" format we support.
    case unsupportedVariableForm(VariableDeclSyntax)

    /// An expression that has an unknown expression.
    case unsupportedExpression(ExprSyntax, expected: String)

    /// A call argument that is unknown/unsupported.
    case unsupportedArgument(LabeledExprSyntax, callee: String)

    /// An invalid Swift language version value.
    case invalidSwiftLanguageVersion(ExprSyntax, value: String)

    /// Unhandled operator-precedence issue.
    case operatorPrecedence(Syntax)
}

extension ManifestParseLimitation: CustomStringConvertible {
    public var description: String {
        let formatter = DiagnosticsFormatter()
        return formatter.formattedMessage(self) + "\n" + formatter.annotatedSource(tree: syntax.root, diags: [asDiagnostic()])
    }
}

/// MARK: Diagnostics
extension ManifestParseLimitation {
    /// The syntax node this limitation describes.
    var syntax: Syntax {
        switch self {
        case .unexpectedSyntax(let node):
            return node
        case .unknownImportModule(let decl, _):
            return Syntax(decl)
        case .unsupportedImportForm(let decl):
            return Syntax(decl)
        case .unsupportedVariableForm(let decl):
            return Syntax(decl)
        case .unsupportedExpression(let expr, _):
            return Syntax(expr)
        case .unsupportedArgument(let arg, callee: _):
            return Syntax(arg)
        case .invalidSwiftLanguageVersion(let expr, _):
            return Syntax(expr)
        case .operatorPrecedence(let node):
            return Syntax(node)
        }
    }

    /// Produce a diagnostic describing this limitation.
    func asDiagnostic() -> Diagnostic {
        Diagnostic(node: syntax, message: self)
    }
}

extension ManifestParseLimitation: DiagnosticMessage {
    public var message: String {
        switch self {
        case .unexpectedSyntax(let node):
            return "Unsupported syntax '\(node.kind)' in package manifest"
        case .unknownImportModule(_, moduleName: let name):
            return "Import of unknown module named '\(name)'"
        case .unsupportedImportForm:
            return "Unsupported import syntax"
        case .unsupportedVariableForm:
            return "Variables can only have the form 'let <name> = <expression>'"
        case .unsupportedExpression(_, expected: let expected):
            return "Unhandled expression in \(expected)"
        case .unsupportedArgument(let arg, callee: let callee):
            if let label = arg.label?.identifier {
                return "Unhandled argument '\(label.name)' in call to '\(callee)"
            }
            return "Unhandled argument in call to '\(callee)'"
        case .invalidSwiftLanguageVersion(_, value: let value):
            return "Invalid Swift language version '\(value)'; expected format is major[.minor[.patch]]"
        case .operatorPrecedence(_):
            return "Unhandled operator precedence issue"
        }
    }

    public var diagnosticID: MessageID {
        let id = switch self {
        case .unexpectedSyntax: "unexpected-syntax"
        case .unknownImportModule: "unknown-import-module"
        case .unsupportedImportForm: "unsupported-import-form"
        case .unsupportedVariableForm: "unsupported-variable-form"
        case .unsupportedExpression: "unsupported-expression"
        case .unsupportedArgument: "unsupported-argument"
        case .invalidSwiftLanguageVersion: "invalid-swift-language-version"
        case .operatorPrecedence: "unhandled-operator-precedence"
        }

        return MessageID(domain: "manifest-parse-limitation", id: id)
    }

    public var severity: DiagnosticSeverity {
        .error
    }

    public var category: DiagnosticCategory? {
        DiagnosticCategory(
            name: "PackageManifest",
            documentationURL: nil
        )
    }
}
