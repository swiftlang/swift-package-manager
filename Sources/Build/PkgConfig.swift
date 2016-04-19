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
}

struct PkgConfig {
    static let searchPaths = ["/usr/local/lib/pkgconfig",
                              "/usr/local/share/pkgconfig",
                              "/usr/lib/pkgconfig",
                              "/usr/share/pkgconfig",
                              ]
    
    let name: String
    let pcFile: String
    var cFlags = [String]()
    var libs = [String]()
    private var parser: PkgConfigParser
    
    init(name: String) throws {
        self.name = name
        self.pcFile = try PkgConfig.locatePCFile(name: name)
        parser = PkgConfigParser(pcFile: pcFile)
    }
    
    static var envSearchPaths: [String] {
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
    
    mutating func load() throws {
        cFlags = [String]()
        libs = [String]()
        try parser.parse()
        if let cFlags = parser.cFlags {
            // FIXME: handle spaces in paths.
            self.cFlags += cFlags.characters.split(separator: " ").map(String.init)
        }
        if let libs = parser.libs {
            // FIXME: handle spaces in paths.
            self.libs += libs.characters.split(separator: " ").map(String.init)
        }
        
        if(parser.dependencies.isEmpty) {
            return
        }
        
        for dep in parser.dependencies {
            var pkg = try PkgConfig(name: dep)
            try pkg.load()
            self.cFlags += pkg.cFlags
            self.libs += pkg.libs
        }
    }
}

private struct PkgConfigParser {
    let pcFile: String
    var variables = [String: String]()
    var dependencies = [String]()
    var cFlags: String?
    var libs: String?
    
    init(pcFile: String) {
        self.pcFile = pcFile
    }
    
    mutating func parse() throws {
        let file = File(path: self.pcFile)
        for line in try file.enumerate() {
            if !line.characters.contains(":") && line.characters.contains("=")  {
                let equalsIndex = line.characters.index(of: "=")!
                let name = line[line.startIndex..<equalsIndex]
                let value = line[equalsIndex.successor()..<line.endIndex]
                variables[name] = resolveVariables(value)
            } else if line.hasPrefix("Requires: ") {
                dependencies = parseDependencies(value(line: line))
            } else if line.hasPrefix("Libs: ") {
                libs = resolveVariables(value(line: line)).chomp()
            } else if line.hasPrefix("Cflags: ") {
                cFlags = resolveVariables( value(line: line)).chomp()
            }
        }
    }
    
    func parseDependencies(_ depString: String) -> [String] {
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
    
    func resolveVariables(_ line: String) -> String {
        func resolve(_ string: String) -> String {
            var resolvedString = string
            guard let dollar = resolvedString.characters.index(of: "$") else { return string }
            guard let variableEndIndex = resolvedString.characters.index(of: "}") else {return string }
            let variable = string[dollar.successor().successor()..<variableEndIndex]
            let value = variables[variable]!
            resolvedString = resolvedString[resolvedString.startIndex..<dollar] + value + resolvedString[variableEndIndex.successor()..<resolvedString.endIndex]
            return resolvedString
        }
        var resolved = line
        while resolved.characters.contains("$") {
            resolved = resolve(resolved)
        }
        return resolved
    }
    
    func value(line: String) -> String {
        guard let colonIndex = line.characters.index(of: ":") else {
            return ""
        }
        return line[colonIndex.successor().successor()..<line.endIndex]
    }
}
