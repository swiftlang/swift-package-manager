//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageModel
import SwiftSyntax
import SwiftSyntaxBuilder

extension TargetDescription.PluginUsage: ManifestSyntaxRepresentable {
    func asSyntax() -> ExprSyntax {
        switch self {
        case let .plugin(name: name, package: package):
            if let package {
                return ".plugin(name: \(literal: name.description), package: \(literal: package.description))"
            } else {
                return ".plugin(name: \(literal: name.description))"
            }
        }
    }
}
