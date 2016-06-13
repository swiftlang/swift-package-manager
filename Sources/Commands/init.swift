/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import POSIX

import func Utility.fopen
import func Utility.fputs
import func Utility.makeDirectories
import struct Utility.Path

fileprivate enum InitError: ErrorProtocol {
    case manifestAlreadyExists
}

extension InitError: CustomStringConvertible {
    var description: String {
        switch self {
        case .manifestAlreadyExists:
            return "a manifest file already exists in this directory"
        }
    }
}

/// Create an initial template package.
final class InitPackage {
    let rootd = POSIX.getcwd()

    /// The mode in use.
    let mode: InitMode

    /// The name of the example package to create.
    let pkgname: String

    /// The name of the example module to create.
    var moduleName: String {
        return pkgname
    }

    /// The name of the example type to create (within the package).
    var typeName: String {
        return pkgname
    }
    
    init(mode: InitMode) throws {
        // Validate that the name is valid.
        let _ = try c99name(name: rootd.basename)
        
        self.mode = mode
        pkgname = rootd.basename
    }
    
    func writePackageStructure() throws {
        print("Creating \(mode) package: \(pkgname)")
        
        try writeManifestFile()
        try writeGitIgnore()
        try writeSources()
        try writeModuleMap()
        try writeTests()
    }
    
    private func writeManifestFile() throws {
        let manifest = Path.join(rootd, Manifest.filename)
        guard manifest.exists == false else {
            throw InitError.manifestAlreadyExists
        }
        
        let packageFP = try Utility.fopen(manifest, mode: .write)
        defer { packageFP.closeFile() }
        print("Creating \(Manifest.filename)")
        // print the manifest file
        try fputs("import PackageDescription\n", packageFP)
        try fputs("\n", packageFP)
        try fputs("let package = Package(\n", packageFP)
        try fputs("    name: \"\(pkgname)\"\n", packageFP)
        try fputs(")\n", packageFP)
    }
    
    private func writeGitIgnore() throws {
        let gitignore = Path.join(rootd, ".gitignore")
        guard gitignore.exists == false else {
            return
        } 
        let gitignoreFP = try Utility.fopen(gitignore, mode: .write)
        defer { gitignoreFP.closeFile() }
    
        print("Creating .gitignore")
        // print the .gitignore
        try fputs(".DS_Store\n", gitignoreFP)
        try fputs("/.build\n", gitignoreFP)
        try fputs("/Packages\n", gitignoreFP)
        try fputs("/*.xcodeproj\n", gitignoreFP)
    }
    
    private func writeSources() throws {
        if mode == .systemModule {
            return
        }
        let sources = Path.join(rootd, "Sources")
        guard sources.exists == false else {
            return
        }
        print("Creating Sources/")
        try Utility.makeDirectories(sources)
    
        let sourceFileName = (mode == .executable) ? "main.swift" : "\(typeName).swift"
        let sourceFile = Path.join(sources, sourceFileName)
        let sourceFileFP = try Utility.fopen(sourceFile, mode: .write)
        defer { sourceFileFP.closeFile() }
        print("Creating Sources/\(sourceFileName)")
        switch mode {
        case .library:
            try fputs("struct \(typeName) {\n\n", sourceFileFP)
            try fputs("    var text = \"Hello, World!\"\n", sourceFileFP)
            try fputs("}\n", sourceFileFP)
        case .executable:
            try fputs("print(\"Hello, world!\")\n", sourceFileFP)
        case .systemModule:
            break
        }
    }
    
    private func writeModuleMap() throws {
        if mode != .systemModule {
            return
        }
        let modulemap = Path.join(rootd, "module.modulemap")
        guard modulemap.exists == false else {
            return
        }
        let modulemapFP = try Utility.fopen(modulemap, mode: .write)
        defer { modulemapFP.closeFile() }
        
        print("Creating module.modulemap")
        // print the module.modulemap
        try fputs("module \(moduleName) [system] {\n", modulemapFP)
        try fputs("  header \"/usr/include/\(moduleName).h\"\n", modulemapFP)
        try fputs("  link \"\(moduleName)\"\n", modulemapFP)
        try fputs("  export *\n", modulemapFP)
        try fputs("}\n", modulemapFP)
    }
    
    private func writeTests() throws {
        if mode == .systemModule {
            return
        }
        let tests = Path.join(rootd, "Tests")
        guard tests.exists == false else {
            return
        }
        print("Creating Tests/")
        try Utility.makeDirectories(tests)
        ///Only libraries are testable for now
        if mode == .library {
            try writeLinuxMain(testsPath: tests)
            try writeTestFileStubs(testsPath: tests)
        }
    }
    
    private func writeLinuxMain(testsPath: String) throws {
        let linuxMain = Path.join(testsPath, "LinuxMain.swift")
        let linuxMainFP = try Utility.fopen(linuxMain, mode: .write)
        defer { linuxMainFP.closeFile() }
        print("Creating Tests/LinuxMain.swift")
        try fputs("import XCTest\n", linuxMainFP)
        try fputs("@testable import \(moduleName)TestSuite\n\n", linuxMainFP)
        try fputs("XCTMain([\n", linuxMainFP)
        try fputs("     testCase(\(typeName)Tests.allTests),\n", linuxMainFP)
        try fputs("])\n", linuxMainFP)
    }
    
    private func writeTestFileStubs(testsPath: String) throws {
        let testModule = Path.join(testsPath, moduleName)
        print("Creating Tests/\(moduleName)/")
        try Utility.makeDirectories(testModule)
        
        let testsFile = Path.join(testModule, "\(moduleName)Tests.swift")
        print("Creating Tests/\(moduleName)/\(moduleName)Tests.swift")
        let testsFileFP = try Utility.fopen(testsFile, mode: .write)
        defer { testsFileFP.closeFile() }
        try fputs("import XCTest\n", testsFileFP)
        try fputs("@testable import \(moduleName)\n", testsFileFP)
        try fputs("\n", testsFileFP)
        try fputs("class \(moduleName)Tests: XCTestCase {\n", testsFileFP)
        try fputs("    func testExample() {\n", testsFileFP)
        try fputs("        // This is an example of a functional test case.\n", testsFileFP)
        try fputs("        // Use XCTAssert and related functions to verify your tests produce the correct results.\n", testsFileFP)
        try fputs("        XCTAssertEqual(\(typeName)().text, \"Hello, World!\")\n", testsFileFP)
        try fputs("    }\n", testsFileFP)
        try fputs("\n", testsFileFP)
        try fputs("\n", testsFileFP)
        try fputs("    static var allTests : [(String, (\(moduleName)Tests) -> () throws -> Void)] {\n", testsFileFP)
        try fputs("        return [\n", testsFileFP)
        try fputs("            (\"testExample\", testExample),\n", testsFileFP)
        try fputs("        ]\n", testsFileFP)
        try fputs("    }\n", testsFileFP)
        try fputs("}\n", testsFileFP)
    }
}

/// Represents a package type for the purposes of initialization.
enum InitMode: CustomStringConvertible {
    case library, executable, systemModule

    init(_ rawValue: String) throws {
        switch rawValue.lowercased() {
        case "library":
            self = .library
        case "executable":
            self = .executable
        case "system-module":
            self = .systemModule
        default:
            throw OptionParserError.invalidUsage("invalid initialization type: \(rawValue)")
        }
    }

    var description: String {
        switch self {
            case .library: return "library"
            case .executable: return "executable"
            case .systemModule: return "system-module"
        }
    }
}
