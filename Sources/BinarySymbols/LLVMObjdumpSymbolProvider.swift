/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics

package struct LLVMObjdumpSymbolProvider: SymbolProvider {
    private let objdumpPath: AbsolutePath

    package init(objdumpPath: AbsolutePath) {
        self.objdumpPath = objdumpPath
    }

    package func symbols(for binary: AbsolutePath, symbols: inout ReferencedSymbols, recordUndefined: Bool = true) async throws {
        let objdumpProcess = AsyncProcess(args: objdumpPath.pathString, "-t", "-T", binary.pathString)
        try objdumpProcess.launch()
        let result = try await objdumpProcess.waitUntilExit()
        guard case .terminated(let status) = result.exitStatus,
            status == 0 else {
            throw InternalError("Unable to run llvm-objdump")
        }

        try parse(output: try result.utf8Output(), symbols: &symbols, recordUndefined: recordUndefined)
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
            throw InternalError("Unable to run llvm-objdump")
        }
        let sectionStart = line.index(line.startIndex, offsetBy: 25)
        guard let sectionEnd = line[sectionStart...].firstIndex(where: \.isWhitespace) else {
            throw InternalError("Unable to run llvm-objdump")
        }
        return line[sectionStart..<sectionEnd]
    }
}

