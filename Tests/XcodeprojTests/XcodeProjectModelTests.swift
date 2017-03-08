/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import TestSupport
@testable import Xcodeproj
import XCTest

class XcodeProjectModelTests: XCTestCase {
    
    func testBasicProjectCreation() {
        // Create a project.
        let proj = Xcode.Project()
        XCTAssert(proj.mainGroup.subitems.isEmpty)
        XCTAssert(proj.mainGroup.pathBase == .groupDir)
        XCTAssert(proj.targets.isEmpty)
        
        // Add a group to the main group.
        let group = proj.mainGroup.addGroup(path: "a group")
        XCTAssert(group.path == "a group")
        XCTAssert(group.pathBase == .groupDir)
        XCTAssert(group.name == nil)
        XCTAssert(group.subitems.isEmpty)
        
        // Check that we can assign a group name.
        group.name = "a group!"
        XCTAssert(group.name == "a group!")
        
        // Check that setting the name didn't change the path.
        XCTAssert(group.path == "a group")
        XCTAssert(group.pathBase == .groupDir)

        // Check that we can change the path.
        group.path = "a group!!"
        XCTAssert(group.path == "a group!!")
        XCTAssert(group.pathBase == .groupDir)

        // Check that setting the path didn't change the name we assigned.
        XCTAssert(group.name == "a group!")

        // Add another group and set a property.
        let subgroup = group.addGroup(path: "a subpath")
        subgroup.name = "subgroup name"
        XCTAssert(subgroup.name == "subgroup name")
        XCTAssert(subgroup.path == "a subpath")
        XCTAssert(subgroup.pathBase == .groupDir)
        
        // Check that we can change the name and path.
        subgroup.name = "new name"
        subgroup.path.append("/subpath")
        XCTAssert(subgroup.name == "new name")
        XCTAssert(subgroup.path == "a subpath/subpath")
        
        // Add a file reference under the subgroup.
        let fileRef = subgroup.addFileReference(path: "MyFile.swift")
        XCTAssert(fileRef.path == "MyFile.swift")
        XCTAssert(fileRef.pathBase == .groupDir)
        XCTAssert(fileRef.name == nil)
        XCTAssert(fileRef.fileType == nil)
        
        // Configure the reference.
        fileRef.path = "Foo/MyFile.swift"
        XCTAssert(fileRef.path == "Foo/MyFile.swift")
        
        // Change the source tree.
        fileRef.pathBase = .projectDir
        
        let _ = proj.generatePlist()
    }
    
    func testTargetCreation() {
        // Create a project.
        let proj = Xcode.Project()
        
        // Add a `Sources` group and some file refs.
        let srcGroup = proj.mainGroup.addGroup(path: "Sources")
        let srcFileRef1 = srcGroup.addFileReference(path: "Source File 1.swift")
        let srcFileRef2 = srcGroup.addFileReference(path: "Source File 2.swift")
        
        // Add a target that builds an executable.
        let target = proj.addTarget(productType: .executable, name: "My App")
        XCTAssert(target.name == "My App")
        XCTAssert(target.productType == .executable)
        XCTAssert(target.buildPhases.isEmpty)
        
        // Add a Sources build phase, and add the file refs to it.
        let srcPhase = target.addSourcesBuildPhase()
        XCTAssert(srcPhase.files.isEmpty)
        let srcBldFile1 = srcPhase.addBuildFile(fileRef: srcFileRef1)
        let srcBldFile2 = srcPhase.addBuildFile(fileRef: srcFileRef2)
        XCTAssert(srcBldFile1.fileRef === srcFileRef1)
        XCTAssert(srcBldFile2.fileRef === srcFileRef2)
        
        // Add an aggregate target (one that doesn't have a product type).
        let aggTarget = proj.addTarget(productType: nil, name: "Aggregate")
        XCTAssert(aggTarget.name == "Aggregate")
        XCTAssert(aggTarget.productType == nil)
        XCTAssert(aggTarget.buildPhases.isEmpty)
        
        let _ = proj.generatePlist()
    }
    
    func testBuildPhases() {
        // Create a project.
        let proj = Xcode.Project()
        
        // Add a `Sources` group and some file refs.
        let srcGroup = proj.mainGroup.addGroup(path: "Sources")
        let srcFileRef1 = srcGroup.addFileReference(path: "SourceFile1.swift")
        let srcFileRef2 = srcGroup.addFileReference(path: "SourceFile2.swift")
        
        // Add a `Resources` group and some file refs.
        let resGroup = proj.mainGroup.addGroup(path: "Resources")
        let resFileRef1 = resGroup.addFileReference(path: "ResFile1.png")
        let resFileRef2 = resGroup.addFileReference(path: "ResFile2.xml")
        
        // Add a target.
        let target = proj.addTarget(productType: .dynamicLibrary, name: "My Lib")
        XCTAssert(target.name == "My Lib")
        XCTAssert(target.productType == .dynamicLibrary)
        XCTAssert(target.buildPhases.isEmpty)
        
        // Add a Sources build phase, and add the file refs to it.
        let srcPhase = target.addSourcesBuildPhase()
        XCTAssert(srcPhase.files.isEmpty)
        let srcBldFile1 = srcPhase.addBuildFile(fileRef: srcFileRef1)
        let srcBldFile2 = srcPhase.addBuildFile(fileRef: srcFileRef2)
        XCTAssert(srcBldFile1.fileRef === srcFileRef1)
        XCTAssert(srcBldFile2.fileRef === srcFileRef2)
        
        // Add a ShellScript build phase, and add the file refs to it.
        let shPhase = target.addShellScriptBuildPhase(script: "echo 'hello'")
        XCTAssert(shPhase.files.isEmpty)
        XCTAssert(shPhase.script == "echo 'hello'")
        
        // Add a CopyFiles build phase.
        let copyPhase = target.addCopyFilesBuildPhase(dstDir: "/tmp")
        XCTAssert(copyPhase.files.isEmpty)
        XCTAssert(copyPhase.dstDir == "/tmp")
        let copyBldFile1 = copyPhase.addBuildFile(fileRef: resFileRef1)
        let copyBldFile2 = copyPhase.addBuildFile(fileRef: resFileRef2)
        XCTAssert(copyBldFile1.fileRef === resFileRef1)
        XCTAssert(copyBldFile2.fileRef === resFileRef2)
        
        let _ = proj.generatePlist()
    }
    
    func testProductReferences() {
        // Create a project.
        let proj = Xcode.Project()
        
        // Add a target.
        let exeTarget = proj.addTarget(productType: .executable, name: "My Exe")
        XCTAssert(exeTarget.name == "My Exe")
        XCTAssert(exeTarget.productType == .executable)
        
        // Associate a product reference.
        
        let _ = proj.generatePlist()
    }
    
    func testTargetDependencies() {
        // Create a project.
        let proj = Xcode.Project()
        
        // Add a target.
        let appTarget = proj.addTarget(productType: .executable, name: "My App")
        XCTAssert(appTarget.name == "My App")
        XCTAssert(appTarget.productType == .executable)
        
        // Add another target.
        let libTarget = proj.addTarget(productType: .framework, name: "My Lib")
        XCTAssert(libTarget.name == "My Lib")
        XCTAssert(libTarget.productType == .framework)
        
        // Make the app target depend on the library target.
        appTarget.addDependency(on: libTarget)
        
        let _ = proj.generatePlist()
    }
    
    func testBuildSettings() {
        // Create a build settings table.
        let settings = Xcode.BuildSettingsTable()
        
        // Make sure we start out empty.
        XCTAssertNil(settings.common.HEADER_SEARCH_PATHS)
        XCTAssertNil(settings.common.PROJECT_NAME)
        
        // Do a couple of basic checks.  These properties are standard Strings
        // [String]s, though, so we don't need too intensive testing.
        settings.common.PROJECT_NAME = "Bla"
        XCTAssertNotNil(settings.common.PROJECT_NAME)
        settings.common.PROJECT_NAME = nil
        XCTAssertNil(settings.common.PROJECT_NAME)
        settings.common.HEADER_SEARCH_PATHS = ["$(inherited)"]
        settings.common.HEADER_SEARCH_PATHS += ["/tmp/path"]
        XCTAssertEqual(settings.common.HEADER_SEARCH_PATHS!, ["$(inherited)", "/tmp/path"])
    }
    
    static var allTests = [
        ("testBasicProjectCreation", testBasicProjectCreation),
        ("testTargetCreation",       testTargetCreation),
        ("testBuildPhases",          testBuildPhases),
        ("testProductReferences",    testProductReferences),
        ("testTargetDependencies",   testTargetDependencies),
        ("testBuildSettings",        testBuildSettings),
    ]
}
