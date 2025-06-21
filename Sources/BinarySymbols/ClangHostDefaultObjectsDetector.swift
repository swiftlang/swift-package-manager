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
    clang: AbsolutePath, fileSystem: any FileSystem, hostTriple: Triple
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

    for argument in linkerArguments {
        if argument.hasPrefix("-L") {
            searchPaths.append(try AbsolutePath(validating: String(argument.dropFirst(2))))
        } else if argument.hasPrefix("-l") && !argument.hasSuffix("lto_library") {
            let libraryName = argument.dropFirst(2)
            let potentialLibraries = searchPaths.flatMap { path in
                if libraryName == "gcc_s" && hostTriple.isLinux() {
                    // Try and pick this up first as libgcc_s tends to be either this or a GNU ld script that pulls this in.
                    return [path.appending("libgcc_s.so.1")]
                } else {
                    return libraryExtensions.map { ext in path.appending("\(hostTriple.dynamicLibraryPrefix)\(libraryName)\(ext)") }
                }
            }

            guard let library = potentialLibraries.first(where: { fileSystem.isFile($0) }) else {
                throw StringError("Couldn't find library: \(libraryName)")
            }

            objects.insert(library)
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

    return objects.compactMap { $0 }
}
