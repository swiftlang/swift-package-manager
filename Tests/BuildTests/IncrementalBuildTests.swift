/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TestSupport
import Basic
import Utility
import func libc.sleep

// FIXME: Seems like these would run a lot faster if they could all get
// executed from an InMemoryFileSystem

/// Functional tests of incremental builds.  These are fairly ad hoc at this
/// point, and because of the time they take, they need to be kept minimal.
/// There are at least a couple of ways in which this could be improved to a
/// greater or lesser degree:
///
/// a) we could look at the llbuild manifest to determine that the right fine-
///    grained dependencies exist (however, this feels a bit too much like a
///    "test that we wrote what we wrote" kind of test, i.e. it doesn't really
///    test that the net effect of triggering rebuilds is achieved; it is also
///    hard to write such tests in a black-box manner, i.e. in terms of the
///    desired effect
///
/// b) a much better way would be if llbuild could quickly report on what files
///    it would update if a build were to be triggered;  this would be a lot
///    faster than actually doing the build, but would of course also bake in
///    an assumption that the needs-to-be-rebuilt state of a file system entity
///    could be determined without running any of the commands (i.e. it would
///    assume that there's no feedback during the build)
///
final class IncrementalBuildTests: XCTestCase {
    override func setUp() {
        super.setUp()
        
    }
    func testIncrementalSingleModuleCLibraryInSources() {
        fixture(name: "ClangModules/CLibrarySources") { prefix in
            print("prefix: \(prefix)")
            // Build it once and capture the log (this will be a full build).
            let fullLog = try executeSwiftBuild(prefix, printIfError: true)
            
            // Check various things that we expect to see in the full build log.
            // FIXME:  This is specific to the format of the log output, which
            // is quite unfortunate but not easily avoidable at the moment.
            XCTAssertTrue(fullLog.contains("Compile CLibrarySources Foo.c"))
            
            // Modify the source file in a way that changes its size so that the low-level
            // build system can detect the change. The timestamp change might be too less
            // for it to detect.
            let sourceFile = prefix.appending(components: "Sources", "Foo.c")
            let stream = BufferedOutputByteStream()
            stream <<< (try localFileSystem.readFileContents(sourceFile)) <<< "\n"
            try localFileSystem.writeFileContents(sourceFile, bytes: stream.bytes)
            // Now build again.  This should be an incremental build.
            let log2 = try executeSwiftBuild(prefix, printIfError: true)
            XCTAssertTrue(log2.contains("Compile CLibrarySources Foo.c"))
            
            // Now build again without changing anything.  This should be a null
            // build.
            let log3 = try executeSwiftBuild(prefix, printIfError: true)
            XCTAssertTrue(log3 == "")
            
        }
    }
    // These were all copy/pasted/tweaked from 
    // testIncrementalSingleModuleCLibraryInSources()
//    func testFixture() {
//        fixture(name: "IncrementalBuildTests/SourceCodeError") { prefix in
//            print("**************TESTFIXTURE PREFIX: \(prefix.asString)")
//            let fullLog = try executeSwiftBuild(prefix, printIfError: true)
//            print(fullLog)
//        }
//    }
    func testAddAndFixSourceCodeError() {
        fixture(name: "IncrementalBuildTests/SourceCodeError") { prefix in
            let initialBuildLog = try executeSwiftBuild(prefix, printIfError: true)
            let sourceFile = prefix.appending(components: "Sources", "SecondLine.swift")
            let preChange = BufferedOutputByteStream()
            let postChange = BufferedOutputByteStream()
            preChange <<< (try localFileSystem.readFileContents(sourceFile))
            postChange <<< (try localFileSystem.readFileContents(sourceFile)) <<< "b"
            try localFileSystem.writeFileContents(sourceFile, bytes: postChange.bytes)
            let postBuildLog = try? executeSwiftBuild(prefix, printIfError: true)
            try localFileSystem.writeFileContents(sourceFile, bytes: preChange.bytes)
            let finalBuildLog = try executeSwiftBuild(prefix, printIfError: true)
            
//            XCTAssert(postBuildLog == nil)
            print(initialBuildLog)
            print(postBuildLog)
            print(finalBuildLog)
        }
    }
    func testAddAndFixPackageError() {
        fixture(name: "IncrementalBuildTests/PackageError") { prefix in
            let initialBuildLog = try? executeSwiftBuild(prefix, printIfError: true)
            print(prefix.appending(component: "Package.swift").asString)
            let sourceFile = prefix.appending(component: "Package.swift")
            let preChange = BufferedOutputByteStream()
            preChange <<< (try localFileSystem.readFileContents(sourceFile))
            print(initialBuildLog ?? "<initialBuildLog == nil>")
            print(preChange.bytes.asReadableString)
//            postChange <<< (try localFileSystem.readFileContents(sourceFile)) <<< "b"
//            try localFileSystem.writeFileContents(sourceFile, bytes: postChange.bytes)
//            let postBuildLog = try? executeSwiftBuild(prefix, printIfError: true)
//            try localFileSystem.writeFileContents(sourceFile, bytes: preChange.bytes)
//            let finalBuildLog = try executeSwiftBuild(prefix, printIfError: true)
//            
//            //            XCTAssert(postBuildLog == nil)
//            print(initialBuildLog)
//            print(postBuildLog)
//            print(finalBuildLog)
        }
    }
    func testAddAndRemoveTargets() {
        
    }
    func testAddAndRemovePackageDependencies() {
        
    }
    func testAddAndRemoveTargetDependencies() {
        
    }
    func testAddAndRemoveSourceFiles() {
        
    }
    

    static var allTests = [
        ("testIncrementalSingleModuleCLibraryInSources", testIncrementalSingleModuleCLibraryInSources),
    ]
}
