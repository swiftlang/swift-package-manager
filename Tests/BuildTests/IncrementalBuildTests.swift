/*
 This source file is part of the Swift.org open source project
 
 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import TestSupport
import Basic
import Utility
import func libc.sleep


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

    func testIncrementalSingleModuleCLibraryInSources() {
        fixture(name: "ClangModules/CLibrarySources") { prefix in
            // Build it once and capture the log (this will be a full build).
            let fullLog = try executeSwiftBuild(prefix, configuration: .Debug, printIfError: true, Xcc: [], Xld: [], Xswiftc: [], env: [:])
            
            // Check various things that we expect to see in the full build log.
            // FIXME:  This is specific to the format of the log output, which
            // is quite unfortunate but not easily avoidable at the moment.
            XCTAssertTrue(fullLog.contains("Compile CLibrarySources Foo.c"))
            XCTAssertTrue(fullLog.contains("Linking CLibrarySources"))
            
            // Now sleep for one second.  This is super-unfortunate, but with
            // the one-second granularity that many file systems have, and with
            // the lower-level build engine still using timestamps to determine
            // when files change, we need to make sure that touching the file
            // results in a new timestamp.
            sleep(1)
            
            // Touch a source file.  Right now the way to do that is to write
            // out the file contents again.
            // FIXME: We can make this better when/if we get a way to set the
            // timestamp of a file in the `FileSystem` class.  However, when
            // the low-level build system starts looking at file contents (as
            // I hope that it will at some point), we may again want to do this
            // by reading the contents, appending a newline, and then writing
            // it out.
            let sourceFile = prefix.appending(components: "Sources", "Foo.c")
            let contents = try localFileSystem.readFileContents(sourceFile)
            try localFileSystem.writeFileContents(sourceFile, bytes: contents)
            
            // Now build again.  This should be an incremental build.
            let log2 = try executeSwiftBuild(prefix, configuration: .Debug, printIfError: true, Xcc: [], Xld: [], Xswiftc: [], env: [:])
            XCTAssertTrue(log2.contains("Compile CLibrarySources Foo.c"))
            XCTAssertTrue(log2.contains("Linking CLibrarySources"))
            
            // Now build again without changing anything.  This should be a null
            // build.
            let log3 = try executeSwiftBuild(prefix, configuration: .Debug, printIfError: true, Xcc: [], Xld: [], Xswiftc: [], env: [:])
            XCTAssertFalse(log3.contains("Compile CLibrarySources Foo.c"))
            XCTAssertFalse(log3.contains("Linking CLibrarySources"))
        }
    }
    
    // FIXME:  We should add a lot more test cases here; the one above is just
    // a starter test.
    
    static var allTests = [
        ("testIncrementalSingleModuleCLibraryInSources", testIncrementalSingleModuleCLibraryInSources),
    ]
}
