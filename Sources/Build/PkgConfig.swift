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
    case ParsingError
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
        
        var cFlags = [String]()
        var libs = [String]()
        
        // FIXME: handle spaces in paths.
        cFlags += parser.cFlags.characters.split(separator: " ").map(String.init)
        libs += parser.libs.characters.split(separator: " ").map(String.init)
        
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
    var cFlags = ""
    var libs = ""
    
    init(pcFile: String) {
        precondition(pcFile.isFile)
        self.pcFile = pcFile
    }
    
    mutating func parse() throws {
        let file = File(path: self.pcFile)
        for line in try file.enumerate() {
            if !line.characters.contains(":") && line.characters.contains("=")  {
                let equalsIndex = line.characters.index(of: "=")!
                let name = line[line.startIndex..<equalsIndex]
                let value = line[equalsIndex.successor()..<line.endIndex]
                variables[name] = try resolveVariables(value)
            } else if line.hasPrefix("Requires: ") {
                dependencies = parseDependencies(value(line: line))
            } else if line.hasPrefix("Libs: ") {
                libs = try resolveVariables(value(line: line)).chomp()
            } else if line.hasPrefix("Cflags: ") {
                cFlags = try resolveVariables( value(line: line)).chomp()
            }
        }
    }
    
    private func parseDependencies(_ depString: String) -> [String] {
        let exploded = depString.characters.split(separator: " ").map(String.init)
        let operators = ["=", "<", ">", "<=", ">="]
        var deps = [String]()
        var skipNext = false
        for depString in exploded {
            if skipNext {
                skipNext = false
                continue
            }
            if operators.contains(depString) {
                skipNext = true
            } else {
                deps.append(depString)
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
            guard dollar != fragment.endIndex && fragment.characters[dollar.successor()] == "{" else { return nil }
            guard let variableEndIndex = fragment.characters.index(of: "}") else { return nil }
            return (fragment[dollar.successor().successor()..<variableEndIndex], dollar, variableEndIndex)
        }

        var result = ""
        var fragment = line
        while !fragment.isEmpty {
            // Look for a variable in our current fragment.
            if let variable = findVariable(fragment) {
                // Append the contents before the variable.
                result += fragment[fragment.characters.startIndex..<variable.startIndex]
                guard let variableValue = variables[variable.name] else { throw PkgConfigError.ParsingError }
                // Append the value of the variable.
                result += variableValue
                // Update the fragment with post variable string.
                fragment = fragment[variable.endIndex.successor()..<fragment.characters.endIndex]
            } else {
                // No variable found, just append rest of the fragment to result.
                result += fragment
                fragment = ""
            }
        }
        return result
    }
    
    private func value(line: String) -> String {
        guard let colonIndex = line.characters.index(of: ":") else {
            return ""
        }
        return line[colonIndex.successor().successor()..<line.endIndex]
    }
}
