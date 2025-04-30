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

extension TargetDescription: ManifestSyntaxRepresentable {
    /// The function name in the package manifest.
    private var functionName: String {
        switch type {
        case .binary: "binaryTarget"
        case .executable: "executableTarget"
        case .macro: "macro"
        case .plugin: "plugin"
        case .regular: "target"
        case .system: "systemLibrary"
        case .test: "testTarget"
        }
    }

    func asSyntax() -> ExprSyntax {
        var arguments: [LabeledExprSyntax] = []
        arguments.append(label: "name", stringLiteral: name)
        // FIXME: pluginCapability

        arguments.appendIfNonEmpty(
            label: "dependencies",
            arrayLiteral: dependencies
        )

        arguments.appendIf(label: "path", stringLiteral: path)
        arguments.appendIf(label: "url", stringLiteral: url)
        arguments.appendIfNonEmpty(label: "exclude", arrayLiteral: exclude)
        arguments.appendIf(label: "sources", arrayLiteral: sources)

        // FIXME: resources

        arguments.appendIf(
            label: "publicHeadersPath",
            stringLiteral: publicHeadersPath
        )

        if !packageAccess {
            arguments.append(
                label: "packageAccess",
                expression: "false"
            )
        }

        // FIXME: cSettings
        // FIXME: cxxSettings
        // FIXME: swiftSettings
        // FIXME: linkerSettings
        // FIXME: plugins

        arguments.appendIf(label: "pkgConfig", stringLiteral: pkgConfig)
        // FIXME: providers

        // Only for plugins
        arguments.appendIf(label: "checksum", stringLiteral: checksum)

        let separateParen: String = arguments.count > 1 ? "\n" : ""
        let argumentsSyntax = LabeledExprListSyntax(arguments)
        return ".\(raw: functionName)(\(argumentsSyntax)\(raw: separateParen))"
    }
}

extension TargetDescription.Dependency: ManifestSyntaxRepresentable {
    func asSyntax() -> ExprSyntax {
        switch self {
        case .byName(name: let name, condition: nil):
            "\(literal: name)"

        case .target(name: let name, condition: nil):
            ".target(name: \(literal: name))"

        case .product(name: let name, package: nil, moduleAliases: nil, condition: nil):
            ".product(name: \(literal: name))"

        case .product(name: let name, package: let package, moduleAliases: nil, condition: nil):
            ".product(name: \(literal: name), package: \(literal: package))"

        default:
            fatalError()
        }
    }
}
