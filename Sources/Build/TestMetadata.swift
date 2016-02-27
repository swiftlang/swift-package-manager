/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageType
import Utility
import POSIX
import func libc.fclose

struct ProductTestMetadata {
    let linuxMainPath: String
    let product: Product
    let metadata: [ModuleTestMetadata]
}

/// Generates one LinuxTestManifest.swift per test module and one LinuxMain.swift
/// for the whole product. All returned paths need to be added for compilation.
func generateLinuxTestFiles(product: Product) throws -> ProductTestMetadata {
    
    // Now parse and generate files for each test module.
    // First parse each module's tests to get the list of classes
    // which we'll use to generate the LinuxMain.swift file later.
    let metadata = try product
        .modules
        .flatMap{ $0 as? TestModule }
        .flatMap { try generateLinuxTestManifests($0) }
    
    //TODO: Decide what to do when users already have
    //the linux XCTestCaseProvider extension. 
    //Ignore that file? Error out and ask them to remove it once and for all?
    //I'd prefer the second, because it'll get everyone on the same page quickly.
    
    // With the test information, generate the LinuxMain file
    let mainPath = try generateLinuxMain(product, metadata: metadata)
    
    return ProductTestMetadata(linuxMainPath: mainPath, product: product, metadata: metadata)
}

/// Updates the contents of and returns the path of LinuxMain.swift file.
func generateLinuxMain(product: Product, metadata: [ModuleTestMetadata]) throws -> String {
    
    // Now get the LinuxMain.swift file's path
    // HACK: To get a path to LinuxMain.swift, we just grab the
    //       parent directory of the first test module we can find.
    let firstTestModule = product.modules.flatMap{ $0 as? TestModule }.first!
    let testDirectory = firstTestModule.sources.root.parentDirectory
    let main = Path.join(testDirectory, "LinuxMain.swift")
    
    // Generate the LinuxMain.swift's contents.
    try writeLinuxMain(metadata, path: main)
    
    return main
}

/// Returns a list of class names that are subclasses of XCTestCase
func generateLinuxTestManifests(module: TestModule) throws -> ModuleTestMetadata? {
    
    let root = module.sources.root
    let testManifestPath = Path.join(root, "LinuxTestManifest.swift")
    
    // Replace the String based parser with AST parser once it's ready
    let parser: TestMetadataParser = StringTestMetadataParser()
    
    let classes = try module
        .sources
        .relativePaths
        .map { Path.join(root, $0) }
        .flatMap { try parser.parseTestClasses($0) }
        .flatMap { $0 }
    
    guard classes.count > 0 else { return nil }
    
    let metadata = ModuleTestMetadata(moduleName: module.name, testManifestPath: testManifestPath, dependencies: module.dependencies.map { $0.name }, classes: classes)
    
    //now generate the LinuxTestManifest.swift file
    try writeLinuxTestManifest(metadata, path: testManifestPath)
    
    return metadata
}

func writeLinuxTestManifest(metadata: ModuleTestMetadata, path: String) throws {
    
    let file = try fopen(path, mode: .Write)
    defer {
        fclose(file)
    }
    
    //imports
    try fputs("import XCTest\n", file)
    try metadata.dependencies.forEach {
        try fputs("@testable import \($0)\n", file)
    }
    try fputs("\n", file)
    
    //conditional compilation for users who will check them in
    try fputs("#if os(Linux)\n", file)
    
    //for each class
    try metadata.classes.sort { $0.name < $1.name }.forEach { classMetadata in
        try fputs("extension \(classMetadata.name): XCTestCaseProvider {\n", file)
        try fputs("    var allTests : [(String, () throws -> Void)] {\n", file)
        try fputs("        return [\n", file)
        
        try classMetadata.testNames.sort().forEach {
            try fputs("            (\"\($0)\", \($0)),\n", file)
        }
        
        try fputs("        ]\n", file)
        try fputs("    }\n", file)
        try fputs("}\n", file)
    }
    
    try fputs("#endif\n\n", file)
}

func writeLinuxMain(metadata: [ModuleTestMetadata], path: String) throws {
    
    let file = try fopen(path, mode: .Write)
    defer {
        fclose(file)
    }
    
    //imports
    try fputs("import XCTest\n", file)
    try metadata.flatMap { $0.moduleName }.sort().forEach {
        //module name e.g. "Jay.test" needs to be imported as "Jaytest"
        //so remove all occurences of '.'
        let name = $0.splitWithCharactersInString(".").joinWithSeparator("")
        try fputs("@testable import \(name)\n", file)
    }
    try fputs("\n", file)
    
    try fputs("XCTMain([\n", file)
    
    //for each class
    try metadata
        .flatMap { $0.classes }
        .sort { $0.name < $1.name }
        .forEach { classMetadata in
            try fputs("    \(classMetadata.name)(),\n", file)
    }
    
    try fputs("])\n\n", file)
}


