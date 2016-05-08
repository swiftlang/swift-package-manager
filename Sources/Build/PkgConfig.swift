/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors 
*/

import Utility
import func POSIX.getenv

enum PkgConfigError: ErrorProtocol {
    case CouldNotFindConfigFile
    case ParsingError(String)
}

struct PkgConfig {
    private static let searchPaths = ["/usr/local/lib/pkgconfig",
                              "/usr/local/share/pkgconfig",
                              "/usr/lib/pkgconfig",
                              "/usr/share/pkgconfig",
                              ]
    let name: String
    let pcFile: String
    let cFlags: [String]
    let libs: [String]
    
    init(name: String) throws {
        self.name = name
        self.pcFile = try PkgConfig.locatePCFile(name: name)
        
        var parser = PkgConfigParser(pcFile: pcFile)
        try parser.parse()
        
        var cFlags = parser.cFlags
        var libs = parser.libs
        
        // If parser found dependencies in pc file, get their flags too.
        if(!parser.dependencies.isEmpty) {
            for dep in parser.dependencies {
                let pkg = try PkgConfig(name: dep)
                cFlags += pkg.cFlags
                libs += pkg.libs
            }
        }
        
        self.cFlags = cFlags
        self.libs = libs
    }
    
    private static var envSearchPaths: [String] {
        if let configPath = getenv("PKG_CONFIG_PATH") {
            return configPath.characters.split(separator: ":").map(String.init)
        }
        return []
    }
    
    static func locatePCFile(name: String) throws -> String {
        for path in (searchPaths + envSearchPaths) {
            let pcFile = Path.join(path, "\(name).pc")
            if pcFile.isFile {
                return pcFile
            }
        }
        throw PkgConfigError.CouldNotFindConfigFile
    }
}

struct PkgConfigParser {
    private let pcFile: String
    private(set) var variables = [String: String]()
    var dependencies = [String]()
    var cFlags = [String]()
    var libs = [String]()
    
    init(pcFile: String) {
        precondition(pcFile.isFile)
        self.pcFile = pcFile
    }
    
    mutating func parse() throws {
        
        func removeComment(line: String) -> String {
            if let commentIndex = line.characters.index(of: "#") {
                return line[line.characters.startIndex..<commentIndex]
            }
            return line
        }
        
        let file = File(path: self.pcFile)
        for line in try file.enumerate() {
            // Remove commented or any trailing comment from the line.
            let uncommentedLine = removeComment(line: line)
            // Ignore any empty or whitespace line.
            guard let line = uncommentedLine.chuzzle() else { continue }
            
            if let colonIndex = line.characters.index(of: ":") where
                line.endIndex == line.characters.index(after: colonIndex) || line[line.characters.index(after: colonIndex)] == " " {
                // Found a key-value pair.
                try parseKeyValue(line: line)
            } else if let equalsIndex = line.characters.index(of: "=") {
                // Found a variable.
                let name = line[line.startIndex..<equalsIndex]
                let value = line[line.index(after: equalsIndex)..<line.endIndex]
                variables[name] = try resolveVariables(value)
            } else {
                // unexpected thing in the pc file, abort.
                throw PkgConfigError.ParsingError("Unexpecting line: \(line) in \(pcFile)")
            }
        }
    }
    
    private mutating func parseKeyValue(line: String) throws {
        if line.hasPrefix("Requires: ") {
            dependencies = try parseDependencies(resolveVariables(value(line: line)))
        } else if line.hasPrefix("Libs: ") {
            libs = try splitEscapingSpace(resolveVariables(value(line: line)))
        } else if line.hasPrefix("Cflags: ") {
            cFlags = try splitEscapingSpace(resolveVariables(value(line: line)))
        }
    }
    
    /// Parses `Requires: ` string into array of dependencies.
    /// The dependency string has seperator which can be (multiple) space or a comma.
    /// Additionally each there can be an optional version constaint to a dependency.
    private func parseDependencies(_ depString: String) throws -> [String] {
        let operators = ["=", "<", ">", "<=", ">="]
        let separators = [" ", ","]
        
        // Look at a char at an index if present.
        func peek(idx: Int) -> Character? {
            guard idx <= depString.characters.count - 1 else { return nil }
            return depString.characters[depString.characters.index(depString.characters.startIndex, offsetBy: idx)]
        }
        
        // This converts the string which can be seperated by comma or spaces
        // into an array of string.
        func tokenize() -> [String] {
            var tokens = [String]()
            var token = ""
            for (idx, char) in depString.characters.enumerated() {
                // Encountered a seperator, use the token.
                if separators.contains(String(char)) {
                    // If next character is a space skip.
                    if let peeked = peek(idx: idx+1) where peeked == " " { continue }
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
                    throw PkgConfigError.ParsingError("Expected version number after \(deps.last) \(arg) in \"\(depString)\" in \(pcFile)")
                }
            } else {
                // Otherwise it is a dependency.
                deps.append(arg)
            }
        }
        return deps
    }
    
    /// Perform variable expansion on the line by processing the each fragment of the string until complete.
    /// Variables occur in form of ${variableName}, we search for a variable linearly
    /// in the string and if found, lookup the value of the variable in our dictionary and
    /// replace the variable name with its value.
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
                    throw PkgConfigError.ParsingError("Expected variable in \(pcFile)")
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
    /// Will break on space in "abc def" and "abc\\ def" but not in "abc\ def" and ignore
    /// multiple spaces such that "abc   def" will split into ["abc", "def"].
    private func splitEscapingSpace(_ line: String) -> [String] {
        var splits = [String]()
        var fragment = [Character]()
        
        func saveFragment() {
            if fragment.count > 0 {
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

    private func value(line: String) -> String {
        guard let colonIndex = line.characters.index(of: ":") else {
            return ""
        }
        return line[line.index(colonIndex, offsetBy: 2)..<line.endIndex]
    }
}
