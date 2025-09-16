/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics

package protocol SymbolProvider {
    func symbols(for: AbsolutePath, symbols: inout ReferencedSymbols, recordUndefined: Bool) async throws
}

extension SymbolProvider {
    package func symbols(for binary: AbsolutePath, symbols: inout ReferencedSymbols) async throws {
        try await self.symbols(for: binary, symbols: &symbols, recordUndefined: true)
    }
}
