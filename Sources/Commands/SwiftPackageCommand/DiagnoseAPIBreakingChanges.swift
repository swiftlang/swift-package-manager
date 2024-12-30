import Foundation
import SPMBuildCore
import TSCBasic
import PackageModel
import Workspace
import TSCUtility
import ArgumentParser
import TSCObservability
import Build

public struct DiagnoseAPIBreakingChanges: ParsableCommand {
    public init() {}
    
    public static let configuration = CommandConfiguration(
        commandName: "diagnose-api-breaking-changes",
        abstract: "Analyzes API breaking changes including git submodules"
    )
    
    public func run() throws {
        // SwiftTool initialization
        let rootPath = try AbsolutePath(validating: FileManager.default.currentDirectoryPath)
        let observabilitySystem = ObservabilitySystem({ print($0) })
        let tool = try SwiftTool(
            rootPath: rootPath,
            observabilityScope: observabilitySystem.topScope
        )
        
        try initializeSubmodules(tool)
        let workspace = try tool.getWorkspace()
        
        let analyzer = APIAnalyzer(workspace: workspace, tool: tool)
        try analyzer.analyze()
    }
    
    private func initializeSubmodules(_ swiftTool: SwiftTool) throws {
        let process = TSCBasic.Process(
            arguments: [
                "/usr/bin/git",
                "submodule",
                "update",
                "--init",
                "--recursive"
            ],
            workingDirectory: swiftTool.packageRoot
        )
        
        try process.launch()
        let result = try process.waitUntilExit()
        
        guard result.exitStatus == TSCBasic.ProcessResult.ExitStatus.terminated(code: 0) else {
            throw DiagnoseError.submoduleInitializationFailed("Git submodule initialization failed")
        }
    }
}

private class APIAnalyzer {
    let workspace: Workspace
    let tool: SwiftTool
    
    init(workspace: Workspace, tool: SwiftTool) {
        self.workspace = workspace
        self.tool = tool
    }
    
    func analyze() throws {
        try analyzeMainPackage()
        try analyzeSubmodules()
    }
    
    private func analyzeMainPackage() throws {
        let mainPackage = try workspace.loadRootPackage(
            at: tool.packageRoot,
            observabilityScope: tool.observabilityScope
        )
        try runAPIDigester(for: mainPackage)
    }
    
    private func analyzeSubmodules() throws {
        let submodules = try findSubmodules()
        for submodule in submodules {
            try runAPIDigester(for: submodule)
        }
    }
    
    private func findSubmodules() throws -> [Package] {
        let digester = APIDigester(
            workingDirectory: tool.packageRoot,
            outputDirectory: tool.packageRoot.appending(component: ".build/api-analysis")
        )
        
        // Submodule yollarını al ve her biri için paket yükle
        let submodulePaths = try digester.findSubmodulePaths()
        return try submodulePaths.compactMap { path in
            try workspace.loadPackage(
                at: path,
                observabilityScope: tool.observabilityScope
            )
        }
    }
    
    private func runAPIDigester(for package: Package) throws {
        let outputDir = tool.packageRoot.appending(component: ".build/api-analysis")
        try makeDirectories(outputDir)
        
        let digester = APIDigester(
            workingDirectory: package.path,
            outputDirectory: outputDir.appending(component: package.identity.description)
        )
        
        let changes = try digester.analyzeAPI()
        reportChanges(changes, for: package)
    }
    
    private func makeDirectories(_ path: AbsolutePath) throws {
        try FileManager.default.createDirectory(
            atPath: path.pathString,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
    
    private func reportChanges(_ changes: [APIChange], for package: Package) {
        guard !changes.isEmpty else { return }
        
        print("\nAPI changes for package: \(package.identity)")
        print("----------------------------------------")
        
        // Değişiklikleri türlerine göre grupla
        let breakingChanges = changes.filter { $0.type == .breaking }
        let nonBreakingChanges = changes.filter { $0.type == .nonBreaking }
        let deprecatedChanges = changes.filter { $0.type == .deprecated }
        
        // Breaking changes
        if !breakingChanges.isEmpty {
            print("\n⚠️  Breaking Changes:")
            for change in breakingChanges {
                printChange(change)
            }
        }
        
        // Non-breaking changes
        if !nonBreakingChanges.isEmpty {
            print("\nℹ️  Non-breaking Changes:")
            for change in nonBreakingChanges {
                printChange(change)
            }
        }
        
        // Deprecated
        if !deprecatedChanges.isEmpty {
            print("\n⚡️ Deprecations:")
            for change in deprecatedChanges {
                printChange(change)
            }
        }
        
        print("\nTotal changes: \(changes.count)")
        print("Breaking changes: \(breakingChanges.count)")
        print("Non-breaking changes: \(nonBreakingChanges.count)")
        print("Deprecations: \(deprecatedChanges.count)")
        print("----------------------------------------\n")
    }
    
    private func printChange(_ change: APIChange) {
        print("  • \(change.description)")
        if let location = change.location {
            print("    at \(location.file):\(location.line):\(location.column)")
        }
    }
}

enum DiagnoseError: LocalizedError {
    case submoduleInitializationFailed(String)
    case apiAnalysisFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .submoduleInitializationFailed(let message):
            return "Failed to initialize submodules: \(message)"
        case .apiAnalysisFailed(let message):
            return "API analysis failed: \(message)"
        }
    }
}
