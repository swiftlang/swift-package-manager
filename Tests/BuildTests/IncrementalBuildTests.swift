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

/// The common error messages.
struct IncBuildErrorMessages {
    static let fullBuildSameAsIncrementalBuild = "A full build was the same as an incremental build"
    static let buildsShouldBeDissimilar = "Two builds with different #s of files shouldn't have the same build log"
    static let unexpectedBuild = "Unexpected build"
    static let unexpectedBuildFailure = "Unexpected build failure"
    static let unexpectedBuildSuccess = "Unexpected build success"
}

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
    /// Can probably be set to `false`, as long as a test checks that building
    /// without changing anything doesn't do anything regardless of this value
    var alwaysDoRedundancyCheck = true
    
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
    func testAddFixSourceCodeError() {
        fixture(name: "IncrementalBuildTests/SourceCodeError") { prefix in
            let sourceFile = prefix.appending(components: "Sources", "SecondLine.swift")
            
            let preChange = BufferedOutputByteStream()
            let postChange = BufferedOutputByteStream()
            preChange <<< (try localFileSystem.readFileContents(sourceFile))
            postChange <<< (try localFileSystem.readFileContents(sourceFile)) <<< "b"
            
            let buildLog1 = try? executeSwiftBuild(prefix, printIfError: true)
            // Introduce an error to one of the files, and try to compile
            try localFileSystem.writeFileContents(sourceFile, bytes: postChange.bytes)
            let buildLog2 = try? executeSwiftBuild(prefix, printIfError: true)
            // Fix the error in the file, and try to compile
            try localFileSystem.writeFileContents(sourceFile, bytes: preChange.bytes)
            let buildLog3 = try? executeSwiftBuild(prefix, printIfError: true)
            // Once more, to verify it doesn't do anything for no changes
            let buildLog4 = alwaysDoRedundancyCheck ? try? executeSwiftBuild(prefix, printIfError: true) : ""
            
            // Check for build failures
            XCTAssert(buildLog1 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog1")
            // FIXME: `buildLog2` *should* be nil, and it used to be. I'm not
            // sure why it isn't failing anymore.
            XCTAssert(buildLog2 == nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildSuccess) for buildLog2: \(buildLog2!)")
            XCTAssert(buildLog3 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog3")
            XCTAssert(buildLog4 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog4")
            
            // build 3 should only compile the 1 edited file
            XCTAssert(buildLog1 != buildLog3, "\(#function): \(IncBuildErrorMessages.fullBuildSameAsIncrementalBuild)")
            // There shouldn't be anything for build 4 to do
            XCTAssert(buildLog4 == "", "\(#function): \(IncBuildErrorMessages.unexpectedBuild) for buildLog4")
        }
    }
    func testAddFixPackageError() {
        fixture(name: "IncrementalBuildTests/PackageError") { prefix in
            let sourceFile = prefix.appending(component: "Package.swift")
            let preChange = BufferedOutputByteStream()
            preChange <<< (try localFileSystem.readFileContents(sourceFile))
            let postChange = BufferedOutputByteStream()
            postChange <<< (try localFileSystem.readFileContents(sourceFile)) <<< "b"

            let buildLog1 = try? executeSwiftBuild(prefix, printIfError: true)
            // Introduce an error in the Package.swift file, and try to compile
            try localFileSystem.writeFileContents(sourceFile, bytes: postChange.bytes)
            let buildLog2 = try? executeSwiftBuild(prefix, printIfError: true)
            // Fix the error, and try to compile
            try localFileSystem.writeFileContents(sourceFile, bytes: preChange.bytes)
            let buildLog3 = try? executeSwiftBuild(prefix, printIfError: true)
            // Once more, to verify it doesn't do anything for no changes
            let buildLog4 = alwaysDoRedundancyCheck ? try? executeSwiftBuild(prefix, printIfError: true) : ""

            // Check for build failures
            XCTAssert(buildLog1 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog1")
            XCTAssert(buildLog2 == nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildSuccess) for buildLog2: \(buildLog2!)")
            XCTAssert(buildLog3 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog3")
            XCTAssert(buildLog4 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog4")

            // The initial build log should build everything, but the post-fix
            // build log should only compile the 1 edited file
            XCTAssert(buildLog1 != buildLog3, "\(#function): \(IncBuildErrorMessages.fullBuildSameAsIncrementalBuild)")
            // There shouldn't be anything to build here, since only
            // Package.swift was edited
            XCTAssert(buildLog3 == "", "\(#function): \(IncBuildErrorMessages.unexpectedBuild) for buildLog3")
            // There shouldn't be anything for build 4 to do
            XCTAssert(buildLog4 == "", "\(#function): \(IncBuildErrorMessages.unexpectedBuild) for buildLog4")
        }
    }
    // FIXME: For some reason, git freaks out on this test and causes "$ swift build"
    // to crash on this one. The error is: Failed to clone /private/var/folders/03/kpjxdjn53nv_l53s4l9kn5p40000gp/T/IncrementalBuildTests_Dependency.xEpVSf/DependencyLib to <AbsolutePath:"/private/var/folders/03/kpjxdjn53nv_l53s4l9kn5p40000gp/T/IncrementalBuildTests_Dependency.xEpVSf/IncrementalBuildTests_Dependency/.build/repositories/DependencyLib--5321191958938219742">
    func testAddAndRemovePackageDependencies() {
        fixture(name: "IncrementalBuildTests/Dependency") { prefix in
            let depPkgPath = prefix.appending(components: "PackageFiles", "PkgDep.swift")
            let noDepPkgPath = prefix.appending(components: "PackageFiles", "NoPkgDep.swift")
            let packagePath = prefix.appending(component: "Package.swift")
            let depPkg = BufferedOutputByteStream()
            let noDepPkg = BufferedOutputByteStream()
            
            do { depPkg <<< (try localFileSystem.readFileContents(depPkgPath)) }
            catch let error { XCTFail("caught: \(error) trying to read \(depPkgPath.asString)") }
            
            do { noDepPkg <<< (try localFileSystem.readFileContents(noDepPkgPath)) }
            catch let error { XCTFail("caught: \(error) trying to read \(noDepPkgPath.asString)") }
            
            try localFileSystem.writeFileContents(packagePath, bytes: depPkg.bytes)
            let buildLog1 = try? executeSwiftBuild(prefix, printIfError: true)
            // remove the dependency
            try localFileSystem.writeFileContents(packagePath, bytes: noDepPkg.bytes)
            let buildLog2 = try? executeSwiftBuild(prefix, printIfError: true)
            // put it back
            try localFileSystem.writeFileContents(packagePath, bytes: depPkg.bytes)
            let buildLog3 = try? executeSwiftBuild(prefix, printIfError: true)
            // Once more, to verify it doesn't do anything for no changes
            let buildLog4 = alwaysDoRedundancyCheck ? try? executeSwiftBuild(prefix, printIfError: true) : ""
            
            XCTAssert(buildLog1 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog1")
            XCTAssert(buildLog2 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog2")
            XCTAssert(buildLog3 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog3")
            XCTAssert(buildLog4 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog4")
            
            // compare the logs
            XCTAssert(buildLog1 != buildLog2, "\(#function): \(IncBuildErrorMessages.buildsShouldBeDissimilar)")
            XCTAssert(buildLog1 != buildLog3, "\(#function): \(IncBuildErrorMessages.fullBuildSameAsIncrementalBuild)")
            // There shouldn't be anything for build 4 to do
            XCTAssert(buildLog4 == "", "\(#function): \(IncBuildErrorMessages.unexpectedBuild) for buildLog4")
        }
    }
    func testAddRemoveFiles() {
        fixture(name: "IncrementalBuildTests/FileAddRemoveTest") { prefix in
            let extraFilePath = prefix.appending(components: "Sources", "FileTesterExt.swift")
            let extraFile = BufferedOutputByteStream()
            
            // We want to be careful with the filesystem here. There's not much
            // we can do to recover from an error writing the file back out, but
            // if we get an error reading the file in in the first place,
            // something has gone really wrong.
            do {
                extraFile <<< (try localFileSystem.readFileContents(extraFilePath))
            } catch let error {
                let message = "\(#function): caught \"\(error)\" trying to read \(extraFilePath.asString). Aborting test"
                fatalError(message)
            }
            
            let buildLog1 = try? executeSwiftBuild(prefix, printIfError: true)
            // Remove a file and recompile
            localFileSystem.removeFileTree(extraFilePath)
            let buildLog2 = try? executeSwiftBuild(prefix, printIfError: true)
            try localFileSystem.writeFileContents(extraFilePath, bytes: extraFile.bytes)
            // Put the file back and recompile
            let buildLog3 = try? executeSwiftBuild(prefix, printIfError: true)
            // Once more, to verify it doesn't do anything for no changes
            let buildLog4 = alwaysDoRedundancyCheck ? try? executeSwiftBuild(prefix, printIfError: true) : ""
            
            // Check for build failures
            XCTAssert(buildLog1 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog1")
            XCTAssert(buildLog2 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog2")
            XCTAssert(buildLog3 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog3")
            XCTAssert(buildLog4 != nil, "\(#function): \(IncBuildErrorMessages.unexpectedBuildFailure) for buildLog4")
            
            // Compare logs
            
            XCTAssert(buildLog1 != buildLog2, "\(#function): \(IncBuildErrorMessages.buildsShouldBeDissimilar)")
            
            // The file that got removed contains an extension that overrides
            // the default implementation of something in a protocol, which is
            // only referenced from main.swift. AFAIK, that means that we should
            // only actually be compiling main.swift and FileTesterExt.
            XCTAssert(buildLog1 != buildLog3, "\(#function): \(IncBuildErrorMessages.fullBuildSameAsIncrementalBuild) for buildLogs 1 and 3")
            // There shouldn't be anything for build 4 to do
            XCTAssert(buildLog4 == "", "\(#function): \(IncBuildErrorMessages.unexpectedBuild) for buildLog4")
            
        }
    }
    func testAddAndRemoveTargetDependencies() {
        
    }
    func testAddAndRemoveTargets() {
        
    }

    static var allTests = [
        ("testIncrementalSingleModuleCLibraryInSources", testIncrementalSingleModuleCLibraryInSources),
    ]
}
