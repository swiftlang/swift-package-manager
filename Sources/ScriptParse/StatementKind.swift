/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 
 FIXME: This is a temporary alternative of the frontend implementation.
*/

import SwiftSyntax

enum StatementKind {
    case package
    case `import`
    case others
}

extension CodeBlockItemSyntax {
    var statementKind: StatementKind {
        let tokens = tokens.map(\.tokenKind)
        if tokens.starts(with: [.importKeyword]) {
            return .import
        } else if tokens.starts(with: [.atSign, .identifier("package")])  {
            return .package
        } else { return .others }
    }
}
