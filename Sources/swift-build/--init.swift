/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct Utility.Path
import func libc.fclose
import PackageType
import POSIX

final class InitPackage {
    let mode: InitMode
    let pkgname: String
    let rootd = POSIX.getcwd()
    
    init(mode: InitMode) throws {
        try c99name(name: rootd.basename)
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
            throw Error.ManifestAlreadyExists
        }
        
        let packageFP = try fopen(manifest, mode: .Write)
        defer {
            fclose(packageFP)
        }
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
        let gitignoreFP = try fopen(gitignore, mode: .Write)
        defer {
            fclose(gitignoreFP)
        }
    
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
        try mkdir(sources)
    
        let sourceFileName = (mode == .Executable) ? "main.swift" : "\(pkgname).swift"
        let sourceFile = Path.join(sources, sourceFileName)
        let sourceFileFP = try fopen(sourceFile, mode: .Write)
        defer {
            fclose(sourceFileFP)
        }
        print("Creating Sources/\(sourceFileName)")
        switch mode {
        case .Library:            
            try fputs("struct \(pkgname) {\n\n", sourceFileFP)
            try fputs("}\n", sourceFileFP)
        case .Executable:
            try fputs("print(\"Hello, world!\")\n", sourceFileFP)
        }
    }
    
    private func writeTests() throws {
        let tests = Path.join(rootd, "Tests")
        guard tests.exists == false else {
            return
        }
        print("Creating Tests/")
        try mkdir(tests)
        ///Only libraries are testable for now
        if mode == .Library {
            try writeLinuxMain(testsPath: tests)
            try writeTestFileStubs(testsPath: tests)
        }
    }
    
    private func writeLinuxMain(testsPath: String) throws {
        let linuxMain = Path.join(testsPath, "LinuxMain.swift")
        let linuxMainFP = try fopen(linuxMain, mode: .Write)
        defer {
            fclose(linuxMainFP)
        }
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
        try mkdir(testModule)
        
        let testsFile = Path.join(testModule, "\(pkgname)Tests.swift")
        print("Creating Tests/\(pkgname)/\(pkgname)Tests.swift")
        let testsFileFP = try fopen(testsFile, mode: .Write)
        defer {
            fclose(testsFileFP)
        }
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
