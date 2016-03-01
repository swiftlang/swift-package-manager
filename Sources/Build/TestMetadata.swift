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

struct TestMetadata {
    
    /// Map from product name -> XCTestMain absolute path
    var productMainPaths: [String: String]

    /// Map from module name -> XCTestManifest absolute path
    var moduleManifestPaths: [String: String]
}

struct ProductTestMetadata {
    let xctestMainPath: String
    let product: Product
    let metadata: [ModuleTestMetadata]
}


/// Generates a XCTestManifest.swift file for each module and XCTestMain.swift file for
/// each product. Note that no files are generated for modules with no XCTestCase
/// subclasses and no files are generated for packages with no XCTest-able modules.
/// Returns TestMetadata, which informs of which files need to be added for 
/// compilation into which module/product.
func generateTestManifestFilesForProducts(products: [Product], prefix: String) throws -> TestMetadata {
    
    //only work with test products
    let testProducts = products.filter { $0.isTest }
    
    //create our .build subfolder
    let testManifestFolder = Path.join(prefix, "xctestmanifests")
    try mkdir(testManifestFolder)
    
    //TODO: what do we do when user deletes an XCTestCase file?
    //we should somehow know to delete its manifest.
    //here we could keep track of touched manifest files and delete the 
    //untouched ones at the end.
    
    //produce manifest file for each test module
    let productsMetadata = try testProducts.flatMap { testProduct in
        return try generateTestManifestFiles(testProduct, testManifestFolder: testManifestFolder)
    }
    
    //collect the paths of generated files
    var productPaths = [String: String]()
    var modulePaths = [String: String]()
    
    for productMetadata in productsMetadata {
        productPaths[productMetadata.product.name] = productMetadata.xctestMainPath
        for moduleMetadata in productMetadata.metadata {
            modulePaths[moduleMetadata.module.name] = moduleMetadata.testManifestPath
        }
    }
    
    return TestMetadata(productMainPaths: productPaths, moduleManifestPaths: modulePaths)
}

/// Generates one XCTestManifest.swift per test module and one XCTestMain.swift
/// for the whole product. All returned paths need to be added for compilation.
func generateTestManifestFiles(product: Product, testManifestFolder: String) throws -> ProductTestMetadata? {
    
    // Now parse and generate files for each test module.
    // First parse each module's tests to get the list of classes
    // which we'll use to generate the XCTestMain.swift file later.
    let metadata = try product
        .modules
        .flatMap{ $0 as? TestModule }
        .flatMap { try generateXCTestManifests($0, testManifestFolder: testManifestFolder) }
    
    // Don't continue if no modules with testable classes were found
    guard metadata.count > 0 else { return nil }
    
    //TODO: Decide what to do when users already have
    //the manual XCTestCaseProvider extension.
    //Ignore that file? Error out and ask them to remove it once and for all?
    //I'd prefer the second, because it'll get everyone on the same page quickly.
    
    // With the test information, generate the XCTestMain file
    let mainPath = try generateXCTestMain(product, metadata: metadata, testManifestFolder: testManifestFolder)
    
    return ProductTestMetadata(xctestMainPath: mainPath, product: product, metadata: metadata)
}

/// Updates the contents of and returns the path of XCTestMain.swift file.
func generateXCTestMain(product: Product, metadata: [ModuleTestMetadata], testManifestFolder: String) throws -> String {
    
    let main = Path.join(testManifestFolder, "\(product.name)-XCTestMain.swift")
    
    // Generate the XCTestMain.swift's contents.
    try writeXCTestMain(metadata, path: main)
    
    return main
}

/// Returns a list of class names that are subclasses of XCTestCase
func generateXCTestManifests(module: TestModule, testManifestFolder: String) throws -> ModuleTestMetadata? {
    
    let root = module.sources.root
    let testManifestPath = Path.join(testManifestFolder, "\(module.name)-XCTestManifest.swift")
    
    // Replace the String based parser with AST parser once it's ready
    let parser: TestMetadataParser = StringTestMetadataParser()
    
    let classes = try module
        .sources
        .relativePaths
        .map { Path.join(root, $0) }
        .flatMap { try parser.parseTestClasses($0) }
        .flatMap { $0 }
    
    guard classes.count > 0 else { return nil }
    
    let metadata = ModuleTestMetadata(module: module, testManifestPath: testManifestPath, classes: classes)
    
    //now generate the XCTestManifest.swift file
    try writeXCTestManifest(metadata, path: testManifestPath)
    
    return metadata
}

func writeXCTestManifest(metadata: ModuleTestMetadata, path: String) throws {
    
    let file = try fopen(path, mode: .Write)
    defer {
        fclose(file)
    }
    
    //imports
    try fputs("import XCTest\n", file)
    try fputs("\n", file)
    
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

func writeXCTestMain(metadata: [ModuleTestMetadata], path: String) throws {
    
    //don't write anything if no classes are available
    guard metadata.count > 0 else { return }

    let file = try fopen(path, mode: .Write)
    defer {
        fclose(file)
    }
    
    //imports
    try fputs("import XCTest\n", file)
    try metadata.flatMap { $0.module.importableName() }.sort().forEach {
        try fputs("@testable import \($0)\n", file)
    }
    try fputs("\n", file)
    
    try fputs("XCTMain([\n", file)
    
    //for each class
    for moduleMetadata in metadata {
        try moduleMetadata
            .classes
            .sort { $0.name < $1.name }
            .forEach { classMetadata in
                try fputs("    \(moduleMetadata.module.importableName()).\(classMetadata.name)(),\n", file)
        }
    }
    
    try fputs("])\n\n", file)
}

extension Module {
    
    func importableName() -> String {
        //module name e.g. "Build.test" needs to be imported as "Buildtest"
        //so remove all occurences of '.'
        let name = self.name.splitWithCharactersInString(".").joinWithSeparator("")
        return name
    }
}


