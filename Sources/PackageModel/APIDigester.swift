import Foundation
import TSCBasic
import TSCUtility

/// A class responsible for analyzing API changes.
public class APIDigester {
    /// The directory in which the digester will operate.
    private let workingDirectory: AbsolutePath
    
    /// The directory where the digester will store output.
    private let outputDirectory: AbsolutePath
    
    public init(workingDirectory: AbsolutePath, outputDirectory: AbsolutePath) {
        self.workingDirectory = workingDirectory
        self.outputDirectory = outputDirectory
    }
    
    /// Analyzes the API.
    /// - Parameter submodules: Whether to include submodules in the analysis.
    /// - Returns: A list of detected API changes.
    public func analyzeAPI(including submodules: Bool = true) throws -> [APIChange] {
        var changes: [APIChange] = []
        
        // Analyze the main package's API.
        changes.append(contentsOf: try analyzeMainPackage())
        
        if submodules {
            // Find and analyze submodules.
            let submodulePaths = try findSubmodulePaths()
            for path in submodulePaths {
                changes.append(contentsOf: try analyzeSubmodule(at: path))
            }
        }
        
        return changes
    }
    
    /// Finds the paths of the Git submodules.
    private func findSubmodulePaths() throws -> [AbsolutePath] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["submodule", "foreach", "--quiet", "pwd"]
        process.currentDirectoryURL = workingDirectory.asURL
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let pathsString = String(data: outputData, encoding: .utf8) else {
            throw APIDigesterError.outputReadError
        }
        
        return pathsString
            .split(separator: "\n")
            .filter { !$0.isEmpty }
            .compactMap { try? AbsolutePath(validating: String($0)) }
    }
    
    /// Analyzes a specific submodule located at the given path.
    private func analyzeSubmodule(at path: AbsolutePath) throws -> [APIChange] {
        let subDigester = APIDigester(
            workingDirectory: path,
            outputDirectory: outputDirectory.appending(component: path.basename)
        )
        return try subDigester.analyzeMainPackage()
    }
    
    /// Analyzes the main package.
    private func analyzeMainPackage() throws -> [APIChange] {
        // 1. Find Swift files in the main package directory.
        let swiftFiles = try findSwiftFiles(in: workingDirectory)
        
        // 2. Load the existing API baseline (if available).
        let baselinePath = outputDirectory.appending(component: "api-baseline.json")
        let baseline = try? loadBaseline(from: baselinePath)
        
        // 3. Analyze the current API from the Swift files.
        let currentAPI = try analyzeCurrentAPI(from: swiftFiles)
        
        // 4. Compare the current API with the baseline to detect changes.
        let changes = try compareAPI(current: currentAPI, baseline: baseline)
        
        // 5. Save the new API baseline.
        try saveBaseline(currentAPI, to: baselinePath)
        
        return changes
    }
    
    /// Finds Swift files within the specified directory.
    private func findSwiftFiles(in directory: AbsolutePath) throws -> [AbsolutePath] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.arguments = [directory.pathString, "-name", "*.swift"]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let filesString = String(data: outputData, encoding: .utf8) else {
            throw APIDigesterError.outputReadError
        }
        
        return filesString
            .split(separator: "\n")
            .filter { !$0.isEmpty }
            .compactMap { try? AbsolutePath(validating: String($0)) }
    }
    
    /// Loads the API baseline from a given path.
    private func loadBaseline(from path: AbsolutePath) throws -> APIBaseline {
        let data = try Data(contentsOf: path.asURL)
        return try JSONDecoder().decode(APIBaseline.self, from: data)
    }
    
    /// Analyzes the current API from the provided list of Swift files.
    private func analyzeCurrentAPI(from files: [AbsolutePath]) throws -> APIBaseline {
        var symbols: [APISymbol] = []
        
        for file in files {
            // Her Swift dosyasını analiz et
            let sourceSymbols = try analyzeSwiftFile(at: file)
            symbols.append(contentsOf: sourceSymbols)
        }
        
        return APIBaseline(
            symbols: symbols,
            version: "1.0.0"
        )
    }
    
    private func analyzeSwiftFile(at path: AbsolutePath) throws -> [APISymbol] {
        let content = try String(contentsOf: path.asURL, encoding: .utf8)
        var symbols: [APISymbol] = []
        
        // Basit bir analiz için satır satır işle
        let lines = content.components(separatedBy: .newlines)
        for (lineNumber, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Public API elemanlarını bul
            if trimmed.hasPrefix("public") {
                if let symbol = try parseSymbol(from: trimmed, at: lineNumber + 1, in: path) {
                    symbols.append(symbol)
                }
            }
        }
        
        return symbols
    }
    
    private func parseSymbol(from line: String, at lineNumber: Int, in file: AbsolutePath) throws -> APISymbol? {
        let components = line.components(separatedBy: .whitespaces)
        guard components.count >= 3 else { return nil }
        
        let accessLevel = AccessLevel.public
        let kind = try determineSymbolKind(from: components)
        let name = try extractSymbolName(from: components, kind: kind)
        
        return APISymbol(
            name: name,
            kind: kind,
            accessLevel: accessLevel,
            location: SourceLocation(
                file: file.pathString,
                line: lineNumber,
                column: 1
            )
        )
    }
    
    private func determineSymbolKind(from components: [String]) throws -> SymbolKind {
        guard components.count >= 2 else {
            throw APIDigesterError.analysisError("Invalid symbol declaration")
        }
        
        switch components[1] {
        case "class": return .class
        case "struct": return .struct
        case "enum": return .enum
        case "protocol": return .protocol
        case "func": return .method
        case "var", "let": return .property
        case "typealias": return .typeAlias
        default:
            throw APIDigesterError.analysisError("Unknown symbol kind: \(components[1])")
        }
    }
    
    private func extractSymbolName(from components: [String], kind: SymbolKind) throws -> String {
        guard components.count >= 3 else {
            throw APIDigesterError.analysisError("Invalid symbol declaration")
        }
        
        var name = components[2]
        // Fonksiyonlar için paranteze kadar olan kısmı al
        if kind == .method {
            name = name.components(separatedBy: "(").first ?? name
        }
        return name
    }
    
    /// Compares the current API with an optional existing baseline to detect changes.
    private func compareAPI(current: APIBaseline, baseline: APIBaseline?) throws -> [APIChange] {
        guard let baseline = baseline else {
            return []
        }
        
        var changes: [APIChange] = []
        
        // Yeni eklenen ve değişen sembolleri kontrol et
        for currentSymbol in current.symbols {
            if let baselineSymbol = baseline.symbols.first(where: { $0.name == currentSymbol.name }) {
                // Sembol zaten var, değişiklikleri kontrol et
                if baselineSymbol.kind != currentSymbol.kind {
                    changes.append(APIChange(
                        type: .breaking,
                        description: "Changed kind of '\(currentSymbol.name)' from \(baselineSymbol.kind) to \(currentSymbol.kind)",
                        location: currentSymbol.location
                    ))
                }
                if baselineSymbol.accessLevel != currentSymbol.accessLevel {
                    changes.append(APIChange(
                        type: .breaking,
                        description: "Changed access level of '\(currentSymbol.name)' from \(baselineSymbol.accessLevel) to \(currentSymbol.accessLevel)",
                        location: currentSymbol.location
                    ))
                }
            } else {
                // Yeni sembol eklenmiş
                changes.append(APIChange(
                    type: .nonBreaking,
                    description: "Added new \(currentSymbol.kind) '\(currentSymbol.name)'",
                    location: currentSymbol.location
                ))
            }
        }
        
        // Silinen sembolleri kontrol et
        for baselineSymbol in baseline.symbols {
            if !current.symbols.contains(where: { $0.name == baselineSymbol.name }) {
                changes.append(APIChange(
                    type: .breaking,
                    description: "Removed \(baselineSymbol.kind) '\(baselineSymbol.name)'",
                    location: baselineSymbol.location
                ))
            }
        }
        
        return changes
    }
    
    /// Saves the provided API baseline to disk at the specified path.
    private func saveBaseline(_ baseline: APIBaseline, to path: AbsolutePath) throws {
        let data = try JSONEncoder().encode(baseline)
        try data.write(to: path.asURL)
    }
}

/// Represents a detected API change.
public struct APIChange: Codable {
    public let type: ChangeType
    public let description: String
    public let location: SourceLocation?
}

/// Enum representing the type of an API change.
public enum ChangeType: String, Codable {
    case breaking
    case nonBreaking
    case deprecated
}

/// Represents a source code location.
public struct SourceLocation: Codable {
    public let file: String
    public let line: Int
    public let column: Int
}

/// Represents an API baseline structure.
public struct APIBaseline: Codable {
    public let symbols: [APISymbol]
    public let version: String
}

/// Represents an API symbol.
public struct APISymbol: Codable {
    public let name: String
    public let kind: SymbolKind
    public let accessLevel: AccessLevel
    public let location: SourceLocation
}

/// Enum representing different kinds of symbols.
public enum SymbolKind: String, Codable {
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case method
    case property
    case typeAlias
}

/// Enum representing different access levels.
public enum AccessLevel: String, Codable {
    case `public`
    case `internal`
    case `private`
    case `fileprivate`
}

/// Enum representing errors that can occur within the APIDigester.
public enum APIDigesterError: LocalizedError {
    case outputReadError
    case analysisError(String)
    case baselineError(String)
    
    public var errorDescription: String? {
        switch self {
        case .outputReadError:
            return "Failed to read process output"
        case .analysisError(let message):
            return "API analysis failed: \(message)"
        case .baselineError(let message):
            return "Baseline operation failed: \(message)"
        }
    }
}

/// Provides a convenience URL property for `AbsolutePath`.
extension AbsolutePath {
    var asURL: URL {
        return URL(fileURLWithPath: pathString)
    }
}
