/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest
import SPMTestSupport
import TSCBasic
import PackageModel
import Workspace

class TemplateTests: XCTestCase {
    func testAddTemplate() throws {
        try XCTSkipIf(InitPackage.createPackageMode == .legacy)
        fixture(name: "Templates/AddTemplate") { prefix in
            try testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let absolutePathToTemplate = prefix.appending(component: "GoodTemplate")
                
                let templatePath = tmpPath.appending(components: "templates", "new-package")
                try fs.createDirectory(templatePath, recursive: true)
                let result = try SwiftPMProduct.SwiftPackage.executeProcess(["add-template", absolutePathToTemplate.pathString, "--config-path", tmpPath.pathString], packagePath: tmpPath)
                
                let errorMessage = try result.utf8stderrOutput()
                XCTAssert(fs.exists(templatePath.appending(component: "goodTemplate")), errorMessage)
            }
        }
    }
    
    func testAddTemplateBadInputs() throws {
        try XCTSkipIf(InitPackage.createPackageMode == .legacy)
        fixture(name: "Templates/AddTemplateErrors") { prefix in
            try testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                
                // When 'add-template' is given a local path it expects that path to be an absolute path to a template directroy
                let missingTemplate = tmpPath.appending(component: "MissingTemplate").pathString
                let invalidPathToTemplate = try SwiftPMProduct.SwiftPackage.executeProcess(["add-template", missingTemplate], packagePath: tmpPath)
                let invalidPathError = try invalidPathToTemplate.utf8stderrOutput()
                
                XCTAssert(invalidPathError.contains("Could not find template: \(missingTemplate)"), invalidPathError)
                
                // Must always have a directroy when using 'add-template'
                let fileTemplate = prefix.appending(component: "Package.swift").pathString
                let noDirSupplied = try SwiftPMProduct.SwiftPackage.executeProcess(["add-template", fileTemplate], packagePath: tmpPath)
                let noDirError = try noDirSupplied.utf8stderrOutput()
                
                XCTAssert(noDirError.contains("\(fileTemplate) is not a valid directory"), noDirError)
                
                // For a template to be valid it must contain 'Package.swift'
                let templatePath = tmpPath.appending(components: "templates", "new-package")
                let absolutePathToTemplate = prefix.appending(component: "MissingManifest")
                try fs.createDirectory(templatePath, recursive: true)
                
                let missingManifest = try SwiftPMProduct.SwiftPackage.executeProcess(["add-template", absolutePathToTemplate.pathString, "--config-path", tmpPath.pathString], packagePath: tmpPath)
                let missingManifestError = try missingManifest.utf8stderrOutput()
                
                XCTAssert(missingManifestError.contains("is not a valid template directory, missing 'Package.swift'"), missingManifestError)
            }
        }
    }
    
    func testInitWithTemplate() throws {
        try XCTSkipIf(InitPackage.createPackageMode == .legacy)
        fixture(name: "Templates/MakePackageWithTemplate") { prefix in
            try testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending(component: "Bar")
                try fs.createDirectory(path)
                
                let result = try SwiftPMProduct.SwiftPackage.executeProcess(["init", "--template", "TestTemplate", "--config-path", prefix.pathString], packagePath: path)
                let stderr = try result.utf8stderrOutput()
                
                XCTAssert(fs.exists(path.appending(component: "Package.swift")), stderr)
                
                
                if let manifest = try fs.readFileContents(path.appending(component: "Package.swift")).validDescription {
                    XCTAssert(manifest.contains("name: \"Bar\","))
                }
                
                XCTAssertBuilds(path)
            }
        }
    }
    
    func testCreateWithTemplate() throws {
        try XCTSkipIf(InitPackage.createPackageMode == .legacy)
        fixture(name: "Templates/MakePackageWithTemplate") { prefix in
            try testWithTemporaryDirectory { tmpPath in
                let fs = localFileSystem
                let path = tmpPath.appending(component: "Foo")
                
                let result = try SwiftPMProduct.SwiftPackage.executeProcess(["create", "Foo", "--template", "TestTemplate", "--config-path", prefix.pathString], packagePath: tmpPath)
                let stderr = try result.utf8stderrOutput()
                
                XCTAssert(fs.exists(path), stderr)
                XCTAssert(fs.exists(path.appending(component: "Package.swift")), stderr)
                XCTAssertBuilds(path)
            }
        }
    }
}
