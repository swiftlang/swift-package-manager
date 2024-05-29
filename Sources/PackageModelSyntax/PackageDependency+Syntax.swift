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
import SwiftParser
import struct TSCUtility.Version

extension PackageDependency: ManifestSyntaxRepresentable {
    func asSyntax() -> ExprSyntax {
        switch self {
        case .fileSystem(let filesystem): filesystem.asSyntax()
        case .sourceControl(let sourceControl): sourceControl.asSyntax()
        case .registry(let registry): registry.asSyntax()
        }
    }
}

extension PackageDependency.FileSystem: ManifestSyntaxRepresentable {
    func asSyntax() -> ExprSyntax {
        fatalError()
    }
}

extension PackageDependency.SourceControl: ManifestSyntaxRepresentable {
    func asSyntax() -> ExprSyntax {
        // TODO: Not handling identity, nameForTargetDependencyResolutionOnly,
        // or productFilter yet.
        switch location {
        case .local(let path):
            ".package(path: \(literal: path.description), \(requirement.asSyntax()))"
        case .remote(let url):
            ".package(url: \(literal: url.description), \(requirement.asSyntax()))"
        }
    }
}

extension PackageDependency.Registry: ManifestSyntaxRepresentable {
    func asSyntax() -> ExprSyntax {
        fatalError()
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

extension Version: ManifestSyntaxRepresentable {
    func asSyntax() -> ExprSyntax {
        return "\(literal: description)"
    }
}
