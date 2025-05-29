/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import protocol TSCBasic.WritableByteStream
import Foundation

package func detectDefaultObjects(
    clang: AbsolutePath, fileSystem: any FileSystem
) async throws -> [AbsolutePath] {
    let clangProcess = AsyncProcess.init(args: clang.pathString, "-###", "-x", "c", "-")
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

    // TODO: extend this to support dylib and other formats for Darwin and dll and lib files on Windows.
    let libraryExtensionsToTry: [String] = [".a", ".so"]
    var objects: Set<AbsolutePath> = []
    var searchPaths: [AbsolutePath] = []
    #if canImport(Darwin)
    // The default linker on darwin embbeds these search paths by default as per `man ld`.
    searchPaths.append(contentsOf: try ["/usr/lib", "/usr/local/lib"].map { try AbsolutePath(validating: $0) })
    #endif

    let linkerArguments = linkerCommand.dropFirst().map {
        $0.replacingOccurrences(of: "\"", with: "")
    }

    for argument in linkerArguments {
        if argument.hasPrefix("-L") {
            searchPaths.append(try AbsolutePath(validating: String(argument.dropFirst(2))))
        } else if argument.hasPrefix("-l") {
            let libName = String(argument.dropFirst(2))
            searchPathLoop: for path in searchPaths {
                for ext in libraryExtensionsToTry {
                    let potentialLibrary = path.appending("lib\(libName)\(ext)")
                    if fileSystem.isFile(potentialLibrary) {
                        objects.insert(potentialLibrary)
                        break searchPathLoop
                    }
                }
            }

            throw StringError("Couldn't find library: \(libName)")
        } else if try argument.hasSuffix(".o")  // TODO: Extend this for obj files on windows
            && fileSystem.isFile(AbsolutePath(validating: argument))
        {
            objects.insert(try AbsolutePath(validating: argument))
        } else if let dotIndex = argument.firstIndex(of: "."),
            libraryExtensionsToTry.first(where: { argument[dotIndex...].contains($0) }) != nil
        {
            objects.insert(try AbsolutePath(validating: argument))
        }
    }

    // On Linux where gcc is the system compiler libgcc_s.so is a linker script that simply pulls libgcc_s.a
    return objects.filter { $0.components.contains("libgcc_s.so") }
}
