/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Foundation

import protocol TSCBasic.WritableByteStream

package func detectDefaultObjects(
    clang: AbsolutePath, fileSystem: any FileSystem, hostTriple: Triple,
    observabilityScope: ObservabilityScope
) async throws -> [AbsolutePath] {
    let clangProcess = AsyncProcess(args: clang.pathString, "-###", "-x", "c", "-")
    let stdinStream = try clangProcess.launch()
    stdinStream.write(
        #"""
        #include <stdio.h>
        int main(int argc, char *argv[]) {
            printf("Hello world!\n")
            return 0;
        }
        """#
    )
    stdinStream.flush()
    try stdinStream.close()
    let clangResult = try await clangProcess.waitUntilExit()
    guard case .terminated(let status) = clangResult.exitStatus,
        status == 0
    else {
        throw StringError("Couldn't run clang on sample hello world program")
    }
    let commandsStrings = try clangResult.utf8stderrOutput().split(whereSeparator: \.isNewline)

    let commands = commandsStrings.map { $0.split(whereSeparator: \.isWhitespace) }
    guard let linkerCommand = commands.last(where: { $0.first?.contains("ld") == true }) else {
        throw StringError("Couldn't find default link command")
    }

    // TODO: This logic doesn't support Darwin and Windows based, c.f. https://github.com/swiftlang/swift-package-manager/issues/8753
    let libraryExtensions = [hostTriple.staticLibraryExtension, hostTriple.dynamicLibraryExtension]
    var objects: Set<AbsolutePath> = []
    var searchPaths: [AbsolutePath] = []

    var linkerArguments = linkerCommand.dropFirst().map {
        $0.replacingOccurrences(of: "\"", with: "")
    }

    if hostTriple.isLinux() {
        // Some platform still separate those out...
        linkerArguments.append(contentsOf: ["-lm", "-lpthread", "-ldl"])
    }

    func handleArgument(_ argument: String) throws {
        if argument.hasPrefix("-L") {
            searchPaths.append(try AbsolutePath(validating: String(argument.dropFirst(2))))
        } else if argument.hasPrefix("-l") && !argument.hasSuffix("lto_library") {
            let libraryName = argument.dropFirst(2)
            let potentialLibraries = searchPaths.flatMap { path in
                return libraryExtensions.map { ext in
                    path.appending("\(hostTriple.dynamicLibraryPrefix)\(libraryName)\(ext)")
                }
            }

            guard let library = potentialLibraries.first(where: { fileSystem.isFile($0) }) else {
                observabilityScope.emit(warning: "Could not find library: \(libraryName)")
                return
            }

            // Try and detect if this a GNU ld linker script.
            if let fileContents = try fileSystem.readFileContents(library).validDescription {
                let lines = fileContents.split(whereSeparator: \.isNewline)
                guard lines.contains(where: { $0.contains("GNU ld script") }) else {
                    objects.insert(library)
                    return
                }

                // If it is try and parse GROUP/INPUT commands as documented in https://sourceware.org/binutils/docs/ld/File-Commands.html
                // Empirically it seems like GROUP is the only used such directive for libraries of interest.
                // Empirically it looks like packaging linker scripts use spaces around parenthesis which greatly simplifies parsing.
                let inputs = lines.filter { $0.hasPrefix("GROUP") || $0.hasPrefix("INPUT") }
                let words = inputs.flatMap { $0.split(whereSeparator: \.isWhitespace) }
                let newArguments = words.filter {
                    !["GROUP", "AS_NEEDED", "INPUT"].contains($0) && $0 != "(" && $0 != ")"
                }.map(String.init)

                for arg in newArguments {
                    if arg.hasPrefix("-l") {
                        try handleArgument(arg)
                    } else {
                        // First try and locate the file relative to the linker script.
                        let siblingPath = try AbsolutePath(
                            validating: arg,
                            relativeTo: try AbsolutePath(validating: library.dirname))
                        if fileSystem.isFile(siblingPath) {
                            try handleArgument(siblingPath.pathString)
                        } else {
                            // If this fails the file needs to be resolved relative to the search paths.
                            guard
                                let library = searchPaths.map({ $0.appending(arg) }).first(where: {
                                    fileSystem.isFile($0)
                                })
                            else {
                                observabilityScope.emit(
                                    warning:
                                        "Malformed linker script at \(library): found no library named \(arg)"
                                )
                                continue
                            }
                            try handleArgument(library.pathString)
                        }
                    }
                }

            } else {
                objects.insert(library)
            }

        } else if try argument.hasSuffix(".o")
            && fileSystem.isFile(AbsolutePath(validating: argument))
        {
            objects.insert(try AbsolutePath(validating: argument))
        } else if let dotIndex = argument.firstIndex(of: "."),
            libraryExtensions.first(where: { argument[dotIndex...].contains($0) }) != nil
        {
            objects.insert(try AbsolutePath(validating: argument))
        }
    }

    for argument in linkerArguments {
        try handleArgument(argument)
    }

    return objects.compactMap { $0 }
}
