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

private enum InitError: ErrorProtocol {
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

final class InitPackage {
    let mode: InitMode
    let pkgname: String
    let rootd = POSIX.getcwd()
    
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
        let sources = Path.join(rootd, "Sources")
        guard sources.exists == false else {
            return
        }
        print("Creating Sources/")
        try Utility.makeDirectories(sources)
    
        let sourceFileName = (mode == .executable) ? "main.swift" : "\(pkgname).swift"
        let sourceFile = Path.join(sources, sourceFileName)
        let sourceFileFP = try Utility.fopen(sourceFile, mode: .write)
        defer { sourceFileFP.closeFile() }
        print("Creating Sources/\(sourceFileName)")
        switch mode {
        case .library:
            try fputs("struct \(pkgname) {\n\n", sourceFileFP)
            try fputs("}\n", sourceFileFP)
        case .executable:
            try fputs("print(\"Hello, world!\")\n", sourceFileFP)
        }
    }
    
    private func writeTests() throws {
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
        try fputs("@testable import \(pkgname)TestSuite\n\n", linuxMainFP)
        try fputs("XCTMain([\n", linuxMainFP)
        try fputs("\t testCase(\(pkgname)Tests.allTests),\n", linuxMainFP)
        try fputs("])\n", linuxMainFP)
    }
    
    private func writeTestFileStubs(testsPath: String) throws {
        let testModule = Path.join(testsPath, pkgname)
        print("Creating Tests/\(pkgname)/")
        try Utility.makeDirectories(testModule)
        
        let testsFile = Path.join(testModule, "\(pkgname)Tests.swift")
        print("Creating Tests/\(pkgname)/\(pkgname)Tests.swift")
        let testsFileFP = try Utility.fopen(testsFile, mode: .write)
        defer { testsFileFP.closeFile() }
        try fputs("import XCTest\n", testsFileFP)
        try fputs("@testable import \(pkgname)\n\n", testsFileFP)
    
        try fputs("class \(pkgname)Tests: XCTestCase {\n\n", testsFileFP)
    
        try fputs("\tfunc testExample() {\n", testsFileFP)
        try fputs("\t\t// This is an example of a functional test case.\n", testsFileFP)
        try fputs("\t\t// Use XCTAssert and related functions to verify your tests produce the correct results.\n", testsFileFP)
        try fputs("\t}\n\n", testsFileFP)
    
        try fputs("}\n", testsFileFP)
    
        try fputs("extension \(pkgname)Tests {\n", testsFileFP)
        try fputs("\tstatic var allTests : [(String, \(pkgname)Tests -> () throws -> Void)] {\n", testsFileFP)
        try fputs("\t\treturn [\n", testsFileFP)
        try fputs("\t\t\t(\"testExample\", testExample),\n", testsFileFP)
        try fputs("\t\t]\n", testsFileFP)
        try fputs("\t}\n", testsFileFP)
        try fputs("}\n", testsFileFP)
    }
}

/// Represents a package type for the purposes of initialization.
enum InitMode: CustomStringConvertible {
    case library, executable

    init(_ rawValue: String?) throws {
        switch rawValue?.lowercased() {
        case "library"?, "lib"?:
            self = .library
        case nil, "executable"?, "exec"?, "exe"?:
            self = .executable
        default:
            throw OptionParserError.invalidUsage("invalid initialization type: \(rawValue)")
        }
    }

    var description: String {
        switch self {
            case .library: return "library"
            case .executable: return "executable"
        }
    }
}
