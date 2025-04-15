package import SystemPackage
private import Foundation

package func detectAdditionalObjects() async throws -> Set<FilePath> {
    guard let sampleExecutable = Bundle.module.url(forResource: "main", withExtension: "c") else {
        throw AdditionalObjectsDetectorError.missingTestFile
    }

    let clangOutput = try await Process.run(executable: "/usr/bin/clang", arguments: "-###", sampleExecutable.path())
    guard let commandStrings = String(data: clangOutput.error, encoding: .utf8)?.split(whereSeparator: \.isNewline) else {
        throw AdditionalObjectsDetectorError.failedToParseClangOutput
    }

    let commands = commandStrings.map { $0.split(whereSeparator: \.isWhitespace) }
    guard let linkerCommand = commands.last(where: { $0.first?.contains("ld") == true }) else {
        throw AdditionalObjectsDetectorError.couldNotFindLinkerCommand
    }

    var libraryExtensionsToTry: [String] = []
#if canImport(Darwin)
    libraryExtensionsToTry.append(contentsOf: [".a", ".dylib", ".tbd"])
#elseif os(Windows)
    libraryExtensionsToTry.append(contentsOf: [".lib", ".dll"])
#else
    libraryExtensionsToTry.append(contentsOf: [".a", ".so"])
#endif

    var objects: Set<FilePath> = []
    var searchPaths: [FilePath] = []
    let fileSystem = LocalFileSystem()

    let linkerArguments = linkerCommand.dropFirst().map { $0.replacingOccurrences(of: "\"", with: "") }

    for argument in linkerArguments {
        if argument.hasPrefix("-L") {
            let path = FilePath(String(argument.dropFirst(2)))
            searchPaths.append(path.lexicallyNormalized())
        } else if argument.hasPrefix("-l") {
            let libName = String(argument.dropFirst(2))
            searchPathLoop: for path in searchPaths {
                for ext in libraryExtensionsToTry {
                    let potentialLibrary = path.appending("lib\(libName)\(ext)")
                    if fileSystem.isRegularFile(potentialLibrary) {
                        objects.insert(potentialLibrary.lexicallyNormalized())
                        break searchPathLoop
                    }
                }
            }

            assertionFailure("Could not find lib for \(libName)")
        } else if argument.hasSuffix(".o") && fileSystem.isRegularFile(FilePath(String(argument))) {
            objects.insert(FilePath(String(argument)).lexicallyNormalized())
        } else if let dotIndex = argument.firstIndex(of: "."),
            ["so", "dylib"].first(where: { argument[dotIndex...].contains($0) }) != nil {
            objects.insert(FilePath(String(argument)).lexicallyNormalized())
        }
    }

    objects.remove("/usr/lib/gcc/aarch64-redhat-linux/7/libgcc_s.so")
    return objects
}

enum AdditionalObjectsDetectorError: Error {
    case missingTestFile
    case failedToParseClangOutput
    case couldNotFindLinkerCommand
}

