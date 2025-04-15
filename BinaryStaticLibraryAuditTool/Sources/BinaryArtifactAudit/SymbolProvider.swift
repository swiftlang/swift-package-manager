package import SystemPackage

package protocol SymbolProvider {
    func symbols(for: FilePath, symbols: inout ReferencedSymbols, recordUndefined: Bool) async throws
}

extension SymbolProvider {
    package func symbols(for binary: FilePath, symbols: inout ReferencedSymbols) async throws {
        try await self.symbols(for: binary, symbols: &symbols, recordUndefined: true)
    }
}

package struct ReferencedSymbols {
    package var defined: Set<String>
    package var undefined: Set<String>

    package init() {
        self.defined = []
        self.undefined = []
    }

    mutating func addUndefined(_ name: String) {
        guard !self.defined.contains(name) else {
            return
        }
        self.undefined.insert(name)
    }

    mutating func addDefined(_ name: String) {
        self.defined.insert(name)
        self.undefined.remove(name)
    }
}
