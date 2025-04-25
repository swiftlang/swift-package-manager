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
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
import struct TSCUtility.Version

extension MappablePackageDependency.Kind: ManifestSyntaxRepresentable {
    func asSyntax() -> ExprSyntax {
        switch self {
        case .fileSystem(name: _, path: let path):
            ".package(path: \(literal: path.description))"
        case .sourceControl(name: _, location: let location, requirement: let requirement):
            ".package(url: \(literal: location.description), \(requirement.asSyntax()))"
        case .registry(id: let id, requirement: let requirement):
            ".package(id: \(literal: id.description), \(requirement.asSyntax()))"
        }
    }
}

extension PackageDependency.SourceControl.Requirement: ManifestSyntaxRepresentable {
    func asSyntax() -> LabeledExprSyntax {
        switch self {
        case .exact(let version):
            LabeledExprSyntax(
                label: "exact",
                expression: version.asSyntax()
            )

        case .range(let range) where range == .upToNextMajor(from: range.lowerBound):
            LabeledExprSyntax(
                label: "from",
                expression: range.lowerBound.asSyntax()
            )

        case .range(let range):
            LabeledExprSyntax(
                expression: "\(range.lowerBound.asSyntax())..<\(range.upperBound.asSyntax())" as ExprSyntax
            )

        case .revision(let revision):
            LabeledExprSyntax(
                label: "revision",
                expression: "\(literal: revision)" as ExprSyntax
            )

        case .branch(let branch):
            LabeledExprSyntax(
                label: "branch",
                expression: "\(literal: branch)" as ExprSyntax
            )
        }
    }
}

extension PackageDependency.Registry.Requirement: ManifestSyntaxRepresentable {
    func asSyntax() -> LabeledExprSyntax {
        switch self {
        case .exact(let version):
            LabeledExprSyntax(
                label: "exact",
                expression: version.asSyntax()
            )

        case .range(let range) where range == .upToNextMajor(from: range.lowerBound):
            LabeledExprSyntax(
                label: "from",
                expression: range.lowerBound.asSyntax()
            )

        case .range(let range):
            LabeledExprSyntax(
                expression: "\(range.lowerBound.asSyntax())..<\(range.upperBound.asSyntax())" as ExprSyntax
            )
        }
    }
}

extension Version: ManifestSyntaxRepresentable {
    func asSyntax() -> ExprSyntax {
        "\(literal: description)"
    }
}
