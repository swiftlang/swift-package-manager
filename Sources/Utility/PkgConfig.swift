/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors 
*/

import Basic

import func POSIX.getenv
import func POSIX.popen

public enum PkgConfigError: Swift.Error {
    case couldNotFindConfigFile
    case parsingError(String)
    case nonWhitelistedFlags(String)
}

/// Get search paths from pkg-config itself.
///
/// This is needed because on Linux machines, the search paths can be different
/// from the standard locations that we are currently searching.
private let pkgConfigSearchPaths: [AbsolutePath] = {
    let searchPaths = try? POSIX.popen(["pkg-config", "--variable", "pc_path", "pkg-config"]).chomp()
    return searchPaths?.characters.split(separator: ":").map{ AbsolutePath(String($0)) } ?? []
}()

/// Information on an individual `pkg-config` supported package.
public struct PkgConfig {
    /// The name of the package.
    public let name: String

    /// The path to the definition file.
    public let pcFile: AbsolutePath

    /// The list of C compiler flags in the definition.
    public let cFlags: [String]

    /// The list of libraries to link.
    public let libs: [String]

    /// The built-in search path list.
    ///
    /// By default, this is combined with the search paths inferred from
    /// `pkg-config` itself.
    private static let searchPaths = [
        AbsolutePath("/usr/local/lib/pkgconfig"),
        AbsolutePath("/usr/local/share/pkgconfig"),
        AbsolutePath("/usr/lib/pkgconfig"),
        AbsolutePath("/usr/share/pkgconfig"),
    ]

    /// Load the information for the named package.
    ///
    /// - name: Name of the pkg config file (without file extension).
    /// - fileSystem: The file system to use, defaults to local file system.
    ///
    /// - throws: PkgConfigError
    public init(name: String, fileSystem: FileSystem = localFileSystem) throws {
        self.name = name
        self.pcFile = try PkgConfig.locatePCFile(name: name, customSearchPaths: PkgConfig.envSearchPaths, fileSystem: fileSystem)

        var parser = PkgConfigParser(pcFile: pcFile, fileSystem: fileSystem)
        try parser.parse()
        
        var cFlags = parser.cFlags
        var libs = parser.libs
        
        // If parser found dependencies in pc file, get their flags too.
        if !parser.dependencies.isEmpty {
            for dep in parser.dependencies {
                // FIXME: This is wasteful, we should be caching the PkgConfig result.
                let pkg = try PkgConfig(name: dep)
                cFlags += pkg.cFlags
                libs += pkg.libs
            }
        }
        
        self.cFlags = cFlags
        self.libs = libs
    }
    
    private static var envSearchPaths: [AbsolutePath] {
        if let configPath = getenv("PKG_CONFIG_PATH") {
            return configPath.characters.split(separator: ":").map{ AbsolutePath(String($0)) }
        }
        return []
    }
    
    static func locatePCFile(name: String, customSearchPaths: [AbsolutePath], fileSystem: FileSystem) throws -> AbsolutePath {
        // FIXME: We should consider building a registry for all items in the
        // search paths, which is likely to be substantially more efficient if
        // we end up searching for a reasonably sized number of packages.
        for path in OrderedSet(customSearchPaths + pkgConfigSearchPaths + searchPaths) {
            let pcFile = path.appending(component: name + ".pc")
            if fileSystem.isFile(pcFile) {
                return pcFile
            }
        }
        throw PkgConfigError.couldNotFindConfigFile
    }
}

/// Parser for the `pkg-config` `.pc` file format.
///
/// See: https://www.freedesktop.org/wiki/Software/pkg-config/
//
// FIXME: This is only internal so it can be unit tested.
struct PkgConfigParser {
    private let pcFile: AbsolutePath
    private let fileSystem: FileSystem
    private(set) var variables = [String: String]()
    var dependencies = [String]()
    var cFlags = [String]()
    var libs = [String]()
    
    init(pcFile: AbsolutePath, fileSystem: FileSystem) {
        precondition(fileSystem.isFile(pcFile))
        self.pcFile = pcFile
        self.fileSystem = fileSystem
    }
    
    mutating func parse() throws {
        func removeComment(line: String) -> String {
            if let commentIndex = line.characters.index(of: "#") {
                return line[line.characters.startIndex..<commentIndex]
            }
            return line
        }
        
        let fileContents = try fileSystem.readFileContents(pcFile)
        // FIXME: Should we error out instead if content is not UTF8 representable?
        for line in fileContents.asString?.components(separatedBy: "\n") ?? [] {
            // Remove commented or any trailing comment from the line.
            let uncommentedLine = removeComment(line: line)
            // Ignore any empty or whitespace line.
            guard let line = uncommentedLine.chuzzle() else { continue }
            
            if line.characters.contains(":") {
                // Found a key-value pair.
                try parseKeyValue(line: line)
            } else if line.characters.contains("=") {
                // Found a variable.
                let (name, maybeValue) = line.split(around: "=")
                let value = maybeValue?.chuzzle() ?? ""
                variables[name.chuzzle() ?? ""] = try resolveVariables(value)
            } else {
                // Unexpected thing in the pc file, abort.
                throw PkgConfigError.parsingError("Unexpected line: \(line) in \(pcFile)")
            }
        }
    }
    
    private mutating func parseKeyValue(line: String) throws {
        precondition(line.characters.contains(":"))
        let (key, maybeValue) = line.split(around: ":")
        let value = try resolveVariables(maybeValue?.chuzzle() ?? "")
        switch key {
        case "Requires":
            dependencies = try parseDependencies(value)
        case "Libs":
            libs = splitEscapingSpace(value)
        case "Cflags":
            cFlags = splitEscapingSpace(value)
        default:
            break
        }
    }
    
    /// Parses `Requires: ` string into array of dependencies.
    ///
    /// The dependency string has seperator which can be (multiple) space or a
    /// comma.  Additionally each there can be an optional version constaint to
    /// a dependency.
    private func parseDependencies(_ depString: String) throws -> [String] {
        let operators = ["=", "<", ">", "<=", ">="]
        let separators = [" ", ","]
        
        // Look at a char at an index if present.
        func peek(idx: Int) -> Character? {
            guard idx <= depString.characters.count - 1 else { return nil }
            return depString.characters[depString.characters.index(depString.characters.startIndex, offsetBy: idx)]
        }
        
        // This converts the string which can be separated by comma or spaces
        // into an array of string.
        func tokenize() -> [String] {
            var tokens = [String]()
            var token = ""
            for (idx, char) in depString.characters.enumerated() {
                // Encountered a seperator, use the token.
                if separators.contains(String(char)) {
                    // If next character is a space skip.
                    if let peeked = peek(idx: idx+1), peeked == " " { continue }
                    // Append to array of tokens and reset token variable.
                    tokens.append(token)
                    token = ""
                } else {
                    token += String(char)
                }
            }
            // Append the last collected token if present.
            if !token.isEmpty { tokens += [token] }
            return tokens
        }

        var deps = [String]()
        var it = tokenize().makeIterator()
        while let arg = it.next() {
            // If we encounter an operator then we need to skip the next token.
            if operators.contains(arg) {
                // We should have a version number next, skip.
                guard let _ = it.next() else {
                    throw PkgConfigError.parsingError("Expected version number after \(deps.last) \(arg) in \"\(depString)\" in \(pcFile)")
                }
            } else {
                // Otherwise it is a dependency.
                deps.append(arg)
            }
        }
        return deps
    }
    
    /// Perform variable expansion on the line by processing the each fragment
    /// of the string until complete.
    ///
    /// Variables occur in form of ${variableName}, we search for a variable
    /// linearly in the string and if found, lookup the value of the variable in
    /// our dictionary and replace the variable name with its value.
    private func resolveVariables(_ line: String) throws -> String {
        typealias StringIndex = String.CharacterView.Index
        
        // Returns variable name, start index and end index of a variable in a string if present.
        // We make sure it of form ${name} otherwise it is not a variable.
        func findVariable(_ fragment: String) -> (name: String, startIndex: StringIndex, endIndex: StringIndex)? {
            guard let dollar = fragment.characters.index(of: "$") else { return nil }
            guard dollar != fragment.endIndex && fragment.characters[fragment.index(after: dollar)] == "{" else { return nil }
            guard let variableEndIndex = fragment.characters.index(of: "}") else { return nil }
            return (fragment[fragment.index(dollar, offsetBy: 2)..<variableEndIndex], dollar, variableEndIndex)
        }

        var result = ""
        var fragment = line
        while !fragment.isEmpty {
            // Look for a variable in our current fragment.
            if let variable = findVariable(fragment) {
                // Append the contents before the variable.
                result += fragment[fragment.characters.startIndex..<variable.startIndex]
                guard let variableValue = variables[variable.name] else {
                    throw PkgConfigError.parsingError("Expected variable in \(pcFile)")
                }
                // Append the value of the variable.
                result += variableValue
                // Update the fragment with post variable string.
                fragment = fragment[fragment.index(after: variable.endIndex)..<fragment.characters.endIndex]
            } else {
                // No variable found, just append rest of the fragment to result.
                result += fragment
                fragment = ""
            }
        }
        return result
    }
    
    /// Split line on unescaped spaces
    ///
    /// Will break on space in "abc def" and "abc\\ def" but not in "abc\ def"
    /// and ignore multiple spaces such that "abc def" will split into ["abc",
    /// "def"].
    private func splitEscapingSpace(_ line: String) -> [String] {
        var splits = [String]()
        var fragment = [Character]()
        
        func saveFragment() {
            if !fragment.isEmpty {
                splits.append(String(fragment))
                fragment.removeAll()
            }
        }
        
        var it = line.characters.makeIterator()
        while let char = it.next() {
            if char == "\\" {
                if let next = it.next() {
                    fragment.append(next)
                }
            } else if char == " " {
                saveFragment()
            } else {
                fragment.append(char)
            }
        }
        saveFragment()
        return splits
    }
}
