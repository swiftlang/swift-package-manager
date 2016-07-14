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

import func Utility.makeDirectories

private extension FileSystem {
    /// Write to a file from a stream producer.
    mutating func writeFileContents(_ path: AbsolutePath, body: @noescape (OutputByteStream) -> ()) throws {
        let contents = OutputByteStream()
        body(contents)
        try createDirectory(path.parentDirectory, recursive: true)
        try writeFileContents(path, bytes: contents.bytes)
    }
}

private enum InitError: Swift.Error {
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
    let rootd = AbsolutePath(POSIX.getcwd())

    /// The mode in use.
    let mode: InitMode

    /// The name of the example package to create.
    let pkgname: String

    /// The name of the example module to create.
    var moduleName: String

    /// The name of the example type to create (within the package).
    var typeName: String {
        return moduleName
    }
    
    init(mode: InitMode) throws {
        self.mode = mode
        pkgname = rootd.basename
        // Also validates that the name is valid.
        moduleName = try c99name(name: rootd.basename)
    }
    
    func writePackageStructure() throws {
        print("Creating \(mode) package: \(pkgname)")

        // FIXME: We should form everything we want to write, then validate that
        // none of it exists, and then act.
        try writeManifestFile()
        try writeGitIgnore()
        try writeSources()
        try writeModuleMap()
        try writeTests()
    }

    private func writePackageFile(_ path: AbsolutePath, body: @noescape (OutputByteStream) -> ()) throws {
        print("Creating \(path.relative(to: rootd).asString)")
        try localFileSystem.writeFileContents(path, body: body)
    }
    
    private func writeManifestFile() throws {
        let manifest = rootd.appending(Manifest.filename)
        guard manifest.asString.exists == false else {
            throw InitError.manifestAlreadyExists
        }

        try writePackageFile(manifest) { stream in
            stream <<< "import PackageDescription\n"
            stream <<< "\n"
            stream <<< "let package = Package(\n"
            stream <<< "    name: \"\(pkgname)\"\n"
            stream <<< ")\n"
        }
    }
    
    private func writeGitIgnore() throws {
        let gitignore = rootd.appending(".gitignore")
        guard gitignore.asString.exists == false else {
            return
        } 
    
        try writePackageFile(gitignore) { stream in
            stream <<< ".DS_Store\n"
            stream <<< "/.build\n"
            stream <<< "/Packages\n"
            stream <<< "/*.xcodeproj\n"
        }
    }
    
    private func writeSources() throws {
        if mode == .systemModule {
            return
        }
        let sources = rootd.appending("Sources")
        guard sources.asString.exists == false else {
            return
        }
        print("Creating Sources/")
        try Utility.makeDirectories(sources.asString)
    
        let sourceFileName = (mode == .executable) ? "main.swift" : "\(typeName).swift"
        let sourceFile = sources.appending(RelativePath(sourceFileName))

        try writePackageFile(sourceFile) { stream in
            switch mode {
            case .library:
                stream <<< "struct \(typeName) {\n\n"
                stream <<< "    var text = \"Hello, World!\"\n"
                stream <<< "}\n"
            case .executable:
                stream <<< "print(\"Hello, world!\")\n"
            case .systemModule:
                break
            }
        }
    }
    
    private func writeModuleMap() throws {
        if mode != .systemModule {
            return
        }
        let modulemap = rootd.appending("module.modulemap")
        guard modulemap.asString.exists == false else {
            return
        }
        
        try writePackageFile(modulemap) { stream in
            stream <<< "module \(moduleName) [system] {\n"
            stream <<< "  header \"/usr/include/\(moduleName).h\"\n"
            stream <<< "  link \"\(moduleName)\"\n"
            stream <<< "  export *\n"
            stream <<< "}\n"
        }
    }
    
    private func writeTests() throws {
        if mode == .systemModule {
            return
        }
        let tests = rootd.appending("Tests")
        guard tests.asString.exists == false else {
            return
        }
        print("Creating Tests/")
        try Utility.makeDirectories(tests.asString)

        // Only libraries are testable for now.
        if mode == .library {
            try writeLinuxMain(testsPath: tests)
            try writeTestFileStubs(testsPath: tests)
        }
    }
    
    private func writeLinuxMain(testsPath: AbsolutePath) throws {
        try writePackageFile(testsPath.appending("LinuxMain.swift")) { stream in
            stream <<< "import XCTest\n"
            stream <<< "@testable import \(moduleName)TestSuite\n\n"
            stream <<< "XCTMain([\n"
            stream <<< "     testCase(\(typeName)Tests.allTests),\n"
            stream <<< "])\n"
        }
    }
    
    private func writeTestFileStubs(testsPath: AbsolutePath) throws {
        let testModule = testsPath.appending(RelativePath(pkgname))
        print("Creating Tests/\(pkgname)/")
        try Utility.makeDirectories(testModule.asString)
        
        try writePackageFile(testModule.appending(RelativePath("\(moduleName)Tests.swift"))) { stream in
            stream <<< "import XCTest\n"
            stream <<< "@testable import \(moduleName)\n"
            stream <<< "\n"
            stream <<< "class \(moduleName)Tests: XCTestCase {\n"
            stream <<< "    func testExample() {\n"
            stream <<< "        // This is an example of a functional test case.\n"
            stream <<< "        // Use XCTAssert and related functions to verify your tests produce the correct results.\n"
            stream <<< "        XCTAssertEqual(\(typeName)().text, \"Hello, World!\")\n"
            stream <<< "    }\n"
            stream <<< "\n"
            stream <<< "\n"
            stream <<< "    static var allTests : [(String, (\(moduleName)Tests) -> () throws -> Void)] {\n"
            stream <<< "        return [\n"
            stream <<< "            (\"testExample\", testExample),\n"
            stream <<< "        ]\n"
            stream <<< "    }\n"
            stream <<< "}\n"
        }
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
