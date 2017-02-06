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

/// returns "line# \\(#line)"
func line(lineNum: Int = #line) -> String {
    return "line# \(lineNum)"
}

/// The common error messages.
enum IncBuildErrorMessages : String, CustomStringConvertible, Hashable {
    static func == (lhs: IncBuildErrorMessages, rhs: IncBuildErrorMessages) -> Bool { return lhs.rawValue == rhs.rawValue }
    var description: String { return self.rawValue }
    var hashValue: Int { return self.rawValue.hashValue }
    case fullBuildSameAsIncrementalBuild = "A full build log was the same as an incremental build log"
    case unexpectedSimilar = "Unexpectedly found two similar build logs"
    case unexpectedDissimilar = "Unexpectedly found two dissimilar build logs"
    case unexpectedBuild = "Unexpected build"
    case unexpectedNullBuild = "Unexpected null build"
    case unexpectedBuildFailure = "Unexpected build failure"
    case unexpectedBuildSuccess = "Unexpected build success"
    case builtTooMany = "The build log contains too many entries"
}

/// Some common build names
enum Builds : String, CustomStringConvertible, Hashable {
    static func == (lhs: Builds, rhs: Builds) -> Bool { return lhs.rawValue == rhs.rawValue }
    var description: String { return self.rawValue }
    var hashValue: Int { return self.rawValue.hashValue }
    case initial = "Initial Full Build"
    case withError = "Build with an Error"
    case withErrorFixed = "Build with the Error Fixed"
    case null = "Null Build"
    case withDependency = "Build with a dependency"
    case withoutDependency = "Build without a dependency"
    case withTargetDependency = "Build with a target dependency"
    case withoutTargetDependency = "Build without a target dependency"
    case withFile = "Build with a file"
    case withoutFile = "Build without a file"
}

/// returns an array of keys whose value is nil. Pass an array of keys to
/// `allowableNils` if it's not an error for something to be nil.
@discardableResult
func checkForNils(_ logs: BuildLog, allowableNils: [Builds] = []) -> [Builds] {
    return logs.keys.filter {
        logs[$0]! == (nil as String?) && !allowableNils.contains($0)
    }
}

func getNumberOfLinkedModules(from: String?) -> Int {
    let logLines = (from ?? "").components(separatedBy: "\n")
    return logLines.filter {$0.hasPrefix("Linking")}.count
}

typealias BuildLog = [Builds : String?]

// Seems like this is too tied to the build's log format
struct BuildResult : Equatable {
    static func == (lhs: BuildResult, rhs: BuildResult) -> Bool {
        return
            lhs.logWasNil == rhs.logWasNil &&
            lhs.isNullBuild == rhs.isNullBuild &&
            lhs.modules.count == rhs.modules.count &&
            zip(lhs.modules, rhs.modules).reduce(true) { $0 && $1.0.fileCount == $1.1.fileCount && $1.0.name == $1.1.name } &&
            lhs.linkedBinaries.count == rhs.linkedBinaries.count &&
            zip(lhs.linkedBinaries, rhs.linkedBinaries).reduce(true) { $0 && $1.0.path == $1.1.path && $1.0.name == $1.1.name }
    }
    
    let logWasNil: Bool
    let isNullBuild: Bool
    let modules: [(name: String, fileCount: Int)]
    let linkedBinaries: [(path: String, name: String)]
    var totalFileCount: Int { return modules.reduce(0) { $0 + $1.fileCount } }
    
    init(_ log: String?) {
        if let log = log {
            logWasNil = false
            isNullBuild = log == ""
            let logLines = log.components(separatedBy: "\n")
            let compileLines = logLines.filter {$0.hasPrefix("Compile Swift Module") && $0.contains("(") && $0.hasSuffix(" sources)") }
            modules = compileLines
                .map { ($0.components(separatedBy: "\'")[1], Int($0.components(separatedBy: "(").last!.components(separatedBy: CharacterSet.whitespaces)[0])!) }
            linkedBinaries = logLines
                .filter { $0.hasPrefix("Linking ") && $0.contains("/") }
                .map {
                    let path = $0.substring(from: $0.range(of: " ")!.upperBound)
                    let name = path.components(separatedBy: "/").last!
                    return (path, name)
            }
        } else {
            logWasNil = true
            isNullBuild = false
            modules = []
            linkedBinaries = []
        }
    }
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

//TODO: Find a way to get actual exit codes, instead of just checking if
// "executeSwiftBuild()" returns nil
final class IncrementalBuildTests: XCTestCase {
    /// Set to true to have every test do a "redudant" build that isn't expected
    /// to do anything. We have a test that explicitly checks regardless of this
    /// value, so it should be safe to leave it as false
    var alwaysDoRedundancyCheck = false
    
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
    
    /// This is the test that explicitly checks that building twice, without
    /// making any changes, doesn't actually do anything
    func testNullBuilds() {
        fixture(name: "IncrementalBuildTests/FileAddRemoveTest") { prefix in
            let buildLogs = [
                Builds.initial : try? executeSwiftBuild(prefix, printIfError: true),
                Builds.null : try? executeSwiftBuild(prefix, printIfError: true)
            ]
            
            checkForNils(buildLogs).forEach { XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)") }
            
            // Compare logs
            XCTAssert(buildLogs[Builds.initial]! != "", "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild): \(Builds.initial)")
            XCTAssert(buildLogs[Builds.initial]! != buildLogs[Builds.null]!, "\(line()): \(IncBuildErrorMessages.unexpectedSimilar): Builds 1 and 2")
            XCTAssert(buildLogs[Builds.null]! == "", "\(line()): \(IncBuildErrorMessages.unexpectedBuild): \(Builds.null)")
        }
    }
    
    func testAddFixSourceCodeError() {
        fixture(name: "IncrementalBuildTests/SourceCodeError") { prefix in
            let sourceFile = prefix.appending(components: "Sources", "SecondLine.swift")
            
            var logs = BuildLog()
            let preChange = BufferedOutputByteStream()
            let postChange = BufferedOutputByteStream()
            preChange <<< (try localFileSystem.readFileContents(sourceFile))
            postChange <<< preChange.bytes.asReadableString <<< "b\n"

            logs[.initial] = try? executeSwiftBuild(prefix, printIfError: true)
            
            // Introduce an error to one of the files, and try to compile
            try localFileSystem.writeFileContents(sourceFile, bytes: postChange.bytes)
            logs[.withError] = try? executeSwiftBuild(prefix, printIfError: true)
            
            // Fix the error in the file, and try to compile
            try localFileSystem.writeFileContents(sourceFile, bytes: preChange.bytes)
            logs[.withErrorFixed] = try? executeSwiftBuild(prefix, printIfError: true)
            
            // Once more, to verify it doesn't do anything for no changes
            logs[.null] = alwaysDoRedundancyCheck ? try? executeSwiftBuild(prefix, printIfError: true) : ""
            
            // Check for build failures
            checkForNils(logs, allowableNils: [.withError]).forEach {
                XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)")
            }
            
            let buildResults: [Builds : BuildResult] = {
                var br = [Builds : BuildResult]()
                logs.forEach {
                    br[$0.key] = BuildResult($0.value)
                }
                return br
            }()
            
            XCTAssert(buildResults[.initial]!.totalFileCount != buildResults[.withErrorFixed]!.totalFileCount, "\(line()): \(IncBuildErrorMessages.fullBuildSameAsIncrementalBuild): \(logs[.initial]! ?? String())")

            XCTAssert(buildResults[.null]!.isNullBuild, "\(line()): \(IncBuildErrorMessages.unexpectedBuild): \(Builds.null)")
        }
    }
    
    func testAddFixPackageError() {
        fixture(name: "IncrementalBuildTests/PackageError") { prefix in
            let sourceFile = prefix.appending(component: "Package.swift")
            let preChange = BufferedOutputByteStream()
            preChange <<< (try localFileSystem.readFileContents(sourceFile))
            let postChange = BufferedOutputByteStream()
            postChange <<< (try localFileSystem.readFileContents(sourceFile)) <<< "b"
            
            var logs = BuildLog()
            
            logs[.initial] = try? executeSwiftBuild(prefix, printIfError: true)
            
            // Introduce an error in the Package.swift file, and try to compile
            try localFileSystem.writeFileContents(sourceFile, bytes: postChange.bytes)
            logs[.withError] = try? executeSwiftBuild(prefix, printIfError: true)
            
            // Fix the error, and try to compile
            try localFileSystem.writeFileContents(sourceFile, bytes: preChange.bytes)
            logs[.withErrorFixed] = try? executeSwiftBuild(prefix, printIfError: true)
            
            // Once more, to verify it doesn't do anything for no changes
            logs[.null] = alwaysDoRedundancyCheck ? try? executeSwiftBuild(prefix, printIfError: true) : ""

            // Check for build failures
            checkForNils(logs, allowableNils: [.withError]).forEach {
                XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)")
            }
            
            // Check logs
            XCTAssert(logs[.initial]! != "", "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild): \(Builds.initial)")
            XCTAssert(logs[.initial]! != logs[.withErrorFixed]!, "\(line()): \(IncBuildErrorMessages.fullBuildSameAsIncrementalBuild): \"\(Builds.initial)\" and \"\(Builds.withErrorFixed)\"")
            // There shouldn't be anything to build here, since we only edited
            // the Package.swift file
            XCTAssert(logs[.withErrorFixed]! == "", "\(line()): \(IncBuildErrorMessages.unexpectedBuild): \(Builds.withErrorFixed)")
            // There shouldn't be anything for build 4 to do
            XCTAssert(logs[.null]! == "", "\(line()): \(IncBuildErrorMessages.unexpectedBuild): \(Builds.null)")
        }
    }
    
    func testAddRemovePackageDependencies() {
        fixture(name: "IncrementalBuildTests/Dep") { prefix in
            let packagePath = prefix.appending(component: "Package.swift")
            let packageDep = BufferedOutputByteStream()
            let packageNoDep = BufferedOutputByteStream()
            packageDep <<< (try localFileSystem.readFileContents(packagePath))
            packageNoDep <<< packageDep.bytes.asReadableString.replacingOccurrences(of: "            dependencies: [.Package(url: \"Packages/DepLib\", majorVersion: 0)]\n", with: "")

            var logs = BuildLog()
            logs[.initial] = try? executeSwiftBuild(prefix, printIfError: true)
            // remove the dependency
            try localFileSystem.writeFileContents(packagePath, bytes: packageNoDep.bytes)
            logs[.withDependency] = try? executeSwiftBuild(prefix, printIfError: true)
            // put it back
            try localFileSystem.writeFileContents(packagePath, bytes: packageDep.bytes)
            logs[.withoutDependency] = try? executeSwiftBuild(prefix, printIfError: true)
            // Once more, to verify it doesn't do anything for no changes
            logs[.null] = alwaysDoRedundancyCheck ? try? executeSwiftBuild(prefix, printIfError: true) : ""
            
            // Check for build failures
            checkForNils(logs).forEach {
                XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)")
            }
            
            // Check the logs
            XCTAssert(logs[.initial]! != "", "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild): build 1")
            // 1st rebuild... there's nothing actually using the dependency, so
            // this should be a null build
            XCTAssert(logs[.withDependency]! == "", "\(line()): \(IncBuildErrorMessages.unexpectedBuild): build 2")
            // 2nd rebuild... should still be a null build
            XCTAssert(logs[.withoutDependency]! == "", "\(line()): \(IncBuildErrorMessages.unexpectedBuild): build 3")
            // There shouldn't be anything for build 4 to do
            XCTAssert(logs[.null]! == "", "\(line()): \(IncBuildErrorMessages.unexpectedBuild): build 4")
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
                let message = "\(line())caught \"\(error)\" trying to read \(extraFilePath.asString). Aborting test"
                XCTFail(message)
                return
            }
            
            var logs = BuildLog()
            logs[.initial] = try? executeSwiftBuild(prefix, printIfError: true)
            // Remove a file and recompile
            localFileSystem.removeFileTree(extraFilePath)
            logs[.withoutFile] = try? executeSwiftBuild(prefix, printIfError: true)
            try localFileSystem.writeFileContents(extraFilePath, bytes: extraFile.bytes)
            // Put the file back and recompile
            logs[.withFile] = try? executeSwiftBuild(prefix, printIfError: true)
            // Once more, to verify it doesn't do anything for no changes
            logs[.null] = alwaysDoRedundancyCheck ? try? executeSwiftBuild(prefix, printIfError: true) : ""
            
            // Check for build failures
            checkForNils(logs).forEach {
                XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)")
            }
            
            // Check logs
            XCTAssert(logs[.initial]! != "", "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild): \(Builds.initial)")
            XCTAssert(logs[.withoutFile]! != "", "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild): \(Builds.withoutFile)")
            XCTAssert(logs[.initial]! != logs[.withoutFile]!, "\(line()): \(IncBuildErrorMessages.unexpectedSimilar): \(logs[.initial]! ?? String())")
            XCTAssert(logs[.withFile]! != "", "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild): \(Builds.withFile)")
            // The file that got removed contains an extension that overrides
            // the default implementation of something in a protocol, which is
            // only referenced from main.swift. AFAIK, that means that we should
            // only actually be compiling main.swift and FileTesterExt. If that's
            // not the case, these two build logs should be == insead of !=
            XCTAssert(logs[.initial]! != logs[.withFile]!, "\(line()): \(IncBuildErrorMessages.fullBuildSameAsIncrementalBuild)")
            // There shouldn't be anything for build 4 to do
            XCTAssert(logs[.null]! == "", "\(line()): \(IncBuildErrorMessages.unexpectedBuild): build 4")
        }
    }

    func testAddRemoveTargets() {
        fixture(name: "IncrementalBuildTests/TrgtDeps") { prefix in
            let packagePath = prefix.appending(component: "Package.swift")
            let packageDep = BufferedOutputByteStream()
            let packageNoDep = BufferedOutputByteStream()
            packageDep <<< (try localFileSystem.readFileContents(packagePath))
            packageNoDep <<< packageDep.bytes.asReadableString.replacingOccurrences(of: "        Target(name: \"Foo_iOS\", dependencies: [\"Foo2Lib\"]),\n", with: "")
            var logs = BuildLog()
            logs[.initial] = try? executeSwiftBuild(prefix, printIfError: true)
            try localFileSystem.writeFileContents(packagePath, bytes: packageNoDep.bytes)
            logs[.withoutDependency] = try? executeSwiftBuild(prefix, printIfError: true)
            try localFileSystem.writeFileContents(packagePath, bytes: packageDep.bytes)
            logs[.withDependency] = try? executeSwiftBuild(prefix, printIfError: true)
            logs[.null] = alwaysDoRedundancyCheck ? try? executeSwiftBuild(prefix, printIfError: true) : ""
            
            // Check for build failures
            checkForNils(logs).forEach {
                XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)")
            }
            
            // Check the logs
            let buildResults: [Builds : BuildResult] = {
                var br = [Builds : BuildResult]()
                logs.forEach { br[$0.key] = BuildResult($0.value) }
                return br
            }()
            
            var correctNum: Int
            // Check the logs
            XCTAssert(!buildResults[.initial]!.isNullBuild, "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild): \(Builds.initial)")
            XCTAssert(buildResults[.initial]! != buildResults[.withoutDependency]!, "\(line()): \(IncBuildErrorMessages.unexpectedSimilar): Builds 1 and 2 - \(logs[.initial]! ?? String())")
            // FIXME: Verify that this is actually correct
            correctNum = 1
            XCTAssert(buildResults[.withoutDependency]!.modules.count == correctNum, "\(line()): \(Builds.withoutDependency) built \(buildResults[.withoutDependency]!.modules.count) modules instead of \(correctNum)")
            // FIXME: Verify that this is actually correct
            //correctNum is still 1
            XCTAssert(buildResults[.withDependency]!.modules.count == correctNum, "\(line()): \(Builds.withDependency) built \(buildResults[.withDependency]!.modules.count) modules instead of \(correctNum)")
            XCTAssert(buildResults[.null]!.isNullBuild, "\(line()): \(IncBuildErrorMessages.unexpectedBuild): build 4")
        }
    }
    
    func testAddRemoveTargetDependencies() {
        fixture(name: "IncrementalBuildTests/TrgtDeps") { prefix in
            var logs = BuildLog()
            let packagePath = prefix.appending(component: "Package.swift")
            let packageDep = BufferedOutputByteStream()
            let packageNoDep = BufferedOutputByteStream()
            packageDep <<< (try localFileSystem.readFileContents(packagePath))
            packageNoDep <<< packageDep.bytes.asReadableString.replacingOccurrences(of: "            \"Foo2Lib\",\n", with: "")
            
            logs[.initial] = try? executeSwiftBuild(prefix, printIfError: true)
            try localFileSystem.writeFileContents(packagePath, bytes: packageNoDep.bytes)
            logs[.withoutDependency] = try? executeSwiftBuild(prefix, printIfError: true)
            try localFileSystem.writeFileContents(packagePath, bytes: packageDep.bytes)
            logs[.withDependency] = try? executeSwiftBuild(prefix, printIfError: true)
            logs[.null] = alwaysDoRedundancyCheck ? try? executeSwiftBuild(prefix, printIfError: true) : ""

            // Check for build failures
            checkForNils(logs).forEach {
                XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)")
            }
            
            // Check the logs
            let buildResults: [Builds : BuildResult] = {
                var br = [Builds : BuildResult]()
                logs.forEach { br[$0.key] = BuildResult($0.value) }
                return br
            }()
            
            var correctNum = 5
            XCTAssert(buildResults[.initial]!.modules.count == correctNum, "\(line()): \(Builds.initial) built \(buildResults[.initial]!.modules.count) binaries instead of \(correctNum): \(logs[.initial]!!)")
            correctNum = 2
            XCTAssert(buildResults[.initial]!.linkedBinaries.count == correctNum, "\(line()): \(Builds.initial) linked \(buildResults[.initial]!.linkedBinaries.count) binaries instead of \(correctNum): \(logs[.initial]!!)")
            
            // Removing a target doesn't need to recompile/rebuild anything, it
            // just removes a binary.
            // FIXME: Verify that this is actually correct
            correctNum = 0
            XCTAssert(buildResults[.withoutDependency]!.linkedBinaries.count == correctNum, "\(line()): \(Builds.withoutDependency) linked \(buildResults[.withoutDependency]!.linkedBinaries.count) binaries instead of \(correctNum): \(logs[.withoutDependency]!!)")
            // FIXME: Verify that this is actually correct
            correctNum = 1
            XCTAssert(buildResults[.withoutDependency]!.modules.count == correctNum, "\(line()): \(Builds.withoutDependency) built \(buildResults[.withoutDependency]!.modules.count) modules instead of \(correctNum): \(logs[.withoutDependency]!!)")
            
            // Adding the target back doesn't seem to do anything, either
            // FIXME: Verify that this is actually correct
            correctNum = 0
            XCTAssert(buildResults[.withDependency]!.linkedBinaries.count == correctNum, "\(line()): \(Builds.withDependency) linked \(buildResults[.withDependency]!.linkedBinaries.count) binaries instead of \(correctNum): \(logs[.withDependency]!!)")
            // FIXME: Verify that this is actually correct
            correctNum = 1
            XCTAssert(buildResults[.withDependency]!.modules.count == correctNum, "\(line()): \(Builds.withDependency) built \(buildResults[.withDependency]!.modules.count) modules instead of \(correctNum): \(logs[.withDependency]!!)")
            
            XCTAssert(buildResults[.null]!.isNullBuild, "\(line()): \(IncBuildErrorMessages.unexpectedBuild): \(Builds.null)")
        }
    }

    static var allTests = [
        ("testIncrementalSingleModuleCLibraryInSources",testIncrementalSingleModuleCLibraryInSources),
        ("testNullBuilds",                              testNullBuilds),
        ("testAddFixPackageError",                      testAddFixPackageError),
        ("testAddFixSourceCodeError",                   testAddFixSourceCodeError),
        ("testAddRemoveFiles",                          testAddRemoveFiles),
        ("testAddRemoveTargets",                        testAddRemoveTargets),
        ("testAddRemovePackageDependencies",            testAddRemovePackageDependencies),
        ("testAddRemoveTargetDependencies",             testAddRemoveTargetDependencies),
    ]
}
