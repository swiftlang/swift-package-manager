private import Foundation
package import SystemPackage

package struct ObjdumpSymbolProvider: SymbolProvider {
    private let objdumpPath: FilePath

    package init(objdumpPath: FilePath) {
        self.objdumpPath = objdumpPath
    }

    package func symbols(for binary: FilePath, symbols: inout ReferencedSymbols, recordUndefined: Bool = true) async throws {
        let result = try await Process.run(executable: objdumpPath, arguments: "-t", "-T", binary.string)
        guard let output = String(data: result.output, encoding: .utf8) else {
            throw Err.unexpectedOutput
        }

        try parse(output: output, symbols: &symbols, recordUndefined: recordUndefined)
    }

    package func parse(output: String, symbols: inout ReferencedSymbols, recordUndefined: Bool = true) throws {
        for line in output.split(whereSeparator: \.isNewline) {
            // Ensure the line starts with an address in the binary everything else isn't a symbol
            guard line.count > 16 && line.prefix(16).allSatisfy(\.isHexDigit),
                let name = name(line: line) else {
                continue
            }

            switch try section(line: line) {
            case "*UND*":
                if recordUndefined {
                    symbols.addUndefined(String(name))
                }
            default:
                symbols.addDefined(String(name))
            }
        }
    }

    private func name(line: Substring) -> Substring? {
        guard let lastspace = line.lastIndex(where: \.isWhitespace) else { return nil }
        return line[line.index(after: lastspace)...]
    }

    private func section(line: Substring) throws -> Substring {
        guard line.count > 25 else {
            throw Err.unexpectedLine(String(line))
        }
        let sectionStart = line.index(line.startIndex, offsetBy: 25)
        guard let sectionEnd = line[sectionStart...].firstIndex(where: \.isWhitespace) else {
            throw Err.unexpectedLine(String(line))
        }
        return line[sectionStart..<sectionEnd]
    }
}

extension ObjdumpSymbolProvider {
    enum Err: Error {
        case unexpectedOutput
        case unexpectedLine(String)
    }
}

