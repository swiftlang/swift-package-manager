//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import RegexBuilder
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

package struct LLVMObjdumpSymbolProvider: SymbolProvider {
    private let objdumpPath: AbsolutePath

    package init(objdumpPath: AbsolutePath) {
        self.objdumpPath = objdumpPath
    }

    package func symbols(for binary: AbsolutePath, symbols: inout ReferencedSymbols, recordUndefined: Bool = true) async throws {
        let result = try await run(
            .path(FilePath(objdumpPath.pathString)),
            arguments: ["-t", "-T", binary.pathString],
            output: .string(limit: .max)
        )
        guard result.terminationStatus.isSuccess else {
            throw InternalError("Unable to run llvm-objdump")
        }

        try parse(output: result.standardOutput ?? "", symbols: &symbols, recordUndefined: recordUndefined)
    }

    package func parse(output: String, symbols: inout ReferencedSymbols, recordUndefined: Bool = true) throws {
        let visibility = Reference<Substring>()
        let weakLinkage = Reference<Substring>()
        let section = Reference<Substring>()
        let name = Reference<Substring>()
        let symbolLineRegex = Regex {
            Anchor.startOfLine
            Repeat(CharacterClass.hexDigit, count: 16) // The address of the symbol
            CharacterClass.whitespace
            Capture(as: visibility) {
                ChoiceOf {
                    "l"
                    "g"
                    "u"
                    "!"
                    " "
                }
            }
            Capture(as: weakLinkage) { // Whether the symbol is weak or strong
                ChoiceOf {
                    "w"
                    " "
                }
            }
            ChoiceOf {
                "C"
                " "
            }
            ChoiceOf {
                "W"
                " "
            }
            ChoiceOf {
                "I"
                "i"
                " "
            }
            ChoiceOf {
                "D"
                "d"
                " "
            }
            ChoiceOf {
                "F"
                "f"
                "O"
                " "
            }
            OneOrMore{
                .whitespace
            }
            Capture(as: section) { // The section the symbol appears in
                ZeroOrMore {
                    .whitespace.inverted
                }
            }
            ZeroOrMore {
                .anyNonNewline
            }
            CharacterClass.whitespace
            Capture(as: name) { // The name of symbol
                OneOrMore {
                    .whitespace.inverted
                }
            }
            Anchor.endOfLine
        }
        for line in output.split(whereSeparator: \.isNewline) {
            guard let match = try symbolLineRegex.wholeMatch(in: line) else {
                // This isn't a symbol definition line
                continue
            }

            switch match[section] {
            case "*UND*":
                guard recordUndefined else {
                    continue
                }
                // Weak symbols are optional
                if match[weakLinkage] != "w" {
                    symbols.addUndefined(String(match[name]))
                }
            default:
                symbols.addDefined(String(match[name]))
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

