/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 
 FIXME: This is a temporary alternative of the frontend implementation.
*/

import SwiftSyntax
import Foundation

func parseStringArgument(_ tokens: inout [TokenSyntax], label: String? = nil) throws -> String? {
    if let label = label {
        // parse label
        guard case .identifier(let labelString) = tokens.first?.tokenKind,
            labelString == label else {
            return nil
        }
        tokens.removeFirst()
        // parse colon
        guard case .colon = tokens.removeFirst().tokenKind else {
            throw ScriptParseError.wrongSyntax
        }
    }
    guard case .stringLiteral(let string) = tokens.removeFirst().tokenKind else {
        throw ScriptParseError.wrongSyntax
    }
    return string.unescaped()
}

private extension String {
    func unescaped() -> String {
        let data = data(using: .utf8)!
        return try! JSONDecoder().decode(String.self, from: data)
    }
}
