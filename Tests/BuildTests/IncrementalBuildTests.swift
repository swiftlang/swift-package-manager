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
import TSCUtility


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
        fixture(name: "CFamilyTargets/CLibrarySources") { prefix in
            // Build it once and capture the log (this will be a full build).
            let (fullLog, _) = try executeSwiftBuild(prefix)

            // Check various things that we expect to see in the full build log.
            // FIXME:  This is specific to the format of the log output, which
            // is quite unfortunate but not easily avoidable at the moment.
            XCTAssertTrue(fullLog.contains("Compiling CLibrarySources Foo.c"))

            let llbuildManifest = prefix.appending(components: ".build", "debug.yaml")

            // Modify the source file in a way that changes its size so that the low-level
            // build system can detect the change (the timestamp change might be too small
            // for the granularity of the file system to represent as distinct values).
            let sourceFile = prefix.appending(components: "Sources", "Foo.c")
            let sourceStream = BufferedOutputByteStream()
            sourceStream <<< (try localFileSystem.readFileContents(sourceFile)) <<< "\n"
            try localFileSystem.writeFileContents(sourceFile, bytes: sourceStream.bytes)

            // Read the first llbuild manifest.
            let llbuildContents1 = try localFileSystem.readFileContents(llbuildManifest)

            // Now build again.  This should be an incremental build.
            let (log2, _) = try executeSwiftBuild(prefix)
            XCTAssertTrue(log2.contains("Compiling CLibrarySources Foo.c"))

            // Read the second llbuild manifest.
            let llbuildContents2 = try localFileSystem.readFileContents(llbuildManifest)

            // Now build again without changing anything.  This should be a null
            // build.
            let (log3, _) = try executeSwiftBuild(prefix)
            XCTAssertFalse(log3.contains("Compiling CLibrarySources Foo.c"))

            // Read the third llbuild manifest.
            let llbuildContents3 = try localFileSystem.readFileContents(llbuildManifest)

            XCTAssertEqual(llbuildContents1, llbuildContents2)
            XCTAssertEqual(llbuildContents2, llbuildContents3)

            // Modify the header file in a way that changes its size so that the low-level
            // build system can detect the change (the timestamp change might be too small
            // for the granularity of the file system to represent as distinct values).
            let headerFile = prefix.appending(components: "Sources", "include", "Foo.h")
            let headerStream = BufferedOutputByteStream()
            headerStream <<< (try localFileSystem.readFileContents(headerFile)) <<< "\n"
            try localFileSystem.writeFileContents(headerFile, bytes: headerStream.bytes)

            // Now build again.  This should be an incremental build.
            let (log4, _) = try executeSwiftBuild(prefix)
            XCTAssertTrue(log4.contains("Compiling CLibrarySources Foo.c"))
        }
    }

    func testBuildManifestCaching() {
        fixture(name: "ValidLayouts/SingleModule/Library") { prefix in
            @discardableResult
            func build() throws -> String {
                return try executeSwiftBuild(prefix, extraArgs: ["--enable-build-manifest-caching"]).stdout
            }

            // Perform a full build.
            try build()
            // Ensure manifest caching kicks in.
            try build()

            // Check that we're not re-planning when nothing has changed.
            let log1 = try build()
            XCTAssertFalse(log1.contains("PackageStructure") || log1.contains("Planning build"), log1)

            // Check that we do run planning when a new source file is added.
            let sourceFile = prefix.appending(components: "Sources", "Library", "new.swift")
            try localFileSystem.writeFileContents(sourceFile, bytes: "")
            let log2 = try build()
            XCTAssertTrue(log2.contains("PackageStructure") || log2.contains("Planning build"), log2)

            // Check that we don't run planning when a source file is modified.
            try localFileSystem.writeFileContents(sourceFile, bytes: "\n\n\n\n")
            let log3 = try build()
            XCTAssertFalse(log3.contains("PackageStructure") || log3.contains("Planning build"), log3)
        }
    }
}
