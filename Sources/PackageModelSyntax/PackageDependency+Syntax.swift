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

extension PackageDependency: ManifestSyntaxRepresentable {
    func asSyntax(manifestDirectory: AbsolutePath) -> ExprSyntax {
        let fragment = SourceCodeFragment(from: self, pathAnchor: manifestDirectory)
        return "\(raw: fragment.generateSourceCode())"
    }
}
