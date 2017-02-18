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

/// Some common error messages.
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
    case builtProductsDiffer = "The ./build/debug/ directories are materially different"
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

/// Set to true to have every test do a "redudant" build that isn't expected
/// to do anything. We have a test that explicitly checks regardless of this
/// value, so it should be safe to leave it as false
var alwaysDoRedundancyCheck = false

/// returns an array of keys whose value is nil. Pass an array of keys to
/// `allowableFailures` if it's not an error for something to be nil.
@discardableResult
func checkForNils(_ logs: BuildLog, allowableFailures: [Builds] = []) -> [Builds] {
    return logs.keys.filter {
        (logs[$0] == nil && !($0 == Builds.null && !alwaysDoRedundancyCheck)) || (logs[$0]!.logWasNil && !allowableFailures.contains($0))
    }
}

typealias BuildLog = [Builds : BuildResult]

// Seems like this is too tied to the build's log format
struct BuildResult : Equatable {
    static func == (lhs: BuildResult, rhs: BuildResult) -> Bool {
        return
            lhs.path == rhs.path &&
            lhs.logWasNil == rhs.logWasNil &&
            lhs.isNullBuild == rhs.isNullBuild &&
            lhs.modules.count == rhs.modules.count &&
            zip(lhs.modules, rhs.modules).reduce(true) { $0 && $1.0.fileCount == $1.1.fileCount && $1.0.name == $1.1.name } &&
            lhs.linkedBinaries.count == rhs.linkedBinaries.count &&
            zip(lhs.linkedBinaries, rhs.linkedBinaries).reduce(true) { $0 && $1.0.path == $1.1.path && $1.0.name == $1.1.name } &&
            lhs.buildProducts == rhs.buildProducts
    }

    let path: AbsolutePath
    let logWasNil: Bool
    let isNullBuild: Bool
    var isNotNullBuild: Bool { return !isNullBuild }
    let modules: [(name: String, fileCount: Int)]
    let linkedBinaries: [(path: String, name: String)]
    var totalFileCount: Int { return modules.reduce(0) { $0 + $1.fileCount } }
    /// An array of the names/paths of files in ./build/debug/ right after a build
    let buildProducts: [String]
    init(_ log: String?, path: AbsolutePath) {
        self.path = path
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
            
            // So the idea here is to log everything in ".builds/debug/", except
            // for "ModuleCache", because that doesn't seem relevant. We crash
            // without the `&& !$0.hasSuffix(".dSYM")` part, probably because
            // localFileSystem.isDirectory() seems to return true for .dSYM files?
            var bp = try! localFileSystem.getDirectoryContents(path.appending(components: ".build", "debug"))
                .filter { $0 != "ModuleCache" }
            // Get the list of "files" that are actually directories...
            var bpd = bp.filter { localFileSystem.isDirectory(path.appending(components: ".build", "debug", $0)) && !$0.hasSuffix(".dSYM") }
            while bpd.count > 0 {
                for dir in bpd {
                    let dirIndex = bp.index(of: dir)!
                    bp.remove(at: dirIndex)
                    // ... for each directory, get of their files...
                    bp.append(contentsOf: (try! localFileSystem.getDirectoryContents(path.appending(components: ".build", "debug", dir))
                        .map {dir + "/" + $0} ))
                }
                //... and repeat
                bpd = bp.filter { localFileSystem.isDirectory(path.appending(components: [".build", "debug"] + $0.components(separatedBy: "/"))) && !$0.hasSuffix(".dSYM") }
            }
            // FIXME: Not entirely sure we should be ignoring these
            buildProducts = bp.filter { !$0.hasSuffix("~") }
        } else {
            logWasNil = true
            isNullBuild = false
            modules = []
            linkedBinaries = []
            buildProducts = []
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
            let logs: BuildLog = [
                Builds.initial : BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix),
                Builds.null : BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            ]
            
            checkForNils(logs).forEach { XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)") }
            
            // Compare logs
            XCTAssert(logs[.initial]!.isNotNullBuild,                                           "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild)")
            XCTAssert(logs[Builds.initial]! != logs[Builds.null]!,                              "\(line()): \(IncBuildErrorMessages.unexpectedSimilar)")
            XCTAssert(logs[Builds.null]!.isNullBuild,                                           "\(line()): \(IncBuildErrorMessages.unexpectedBuild)")
            XCTAssert(logs[Builds.initial]!.buildProducts == logs[Builds.null]!.buildProducts,  "\(line()): \(IncBuildErrorMessages.builtProductsDiffer)")
        }
    }

    func testAddFixSourceCodeError() {
        fixture(name: "IncrementalBuildTests/SourceCodeError") { prefix in
            let sourceFile = prefix.appending(components: "Sources", "SecondLine.swift")
            let preChange = BufferedOutputByteStream()
            let postChange = BufferedOutputByteStream()
            preChange <<< (try localFileSystem.readFileContents(sourceFile))
            postChange <<< preChange.bytes.asReadableString <<< "b\n"

            var logs = BuildLog()

            logs[.initial] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            
            // Introduce an error to one of the files, and try to compile
            try localFileSystem.writeFileContents(sourceFile, bytes: postChange.bytes)
            logs[.withError] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            
            // Fix the error in the file, and try to compile
            try localFileSystem.writeFileContents(sourceFile, bytes: preChange.bytes)
            logs[.withErrorFixed] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            
            // Once more, to verify it doesn't do anything for no changes
            logs[.null] = alwaysDoRedundancyCheck ? BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix) : nil
            
            // Check for unexpected build failures
            checkForNils(logs, allowableFailures: [.withError]).forEach {
                XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)")
            }

            XCTAssert(logs[.initial]!.totalFileCount != logs[.withErrorFixed]!.totalFileCount,  "\(line()): \(IncBuildErrorMessages.fullBuildSameAsIncrementalBuild)")
            XCTAssert(logs[.initial]!.buildProducts == logs[.withErrorFixed]!.buildProducts,    "\(line()): \(IncBuildErrorMessages.builtProductsDiffer)")
            XCTAssert(logs[.null]?.isNullBuild ?? true,                                         "\(line()): \(IncBuildErrorMessages.unexpectedBuild)")
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
            
            logs[.initial] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            
            // Introduce an error in the Package.swift file, and try to compile
            try localFileSystem.writeFileContents(sourceFile, bytes: postChange.bytes)
            logs[.withError] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            
            // Fix the error, and try to compile
            try localFileSystem.writeFileContents(sourceFile, bytes: preChange.bytes)
            logs[.withErrorFixed] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            
            // Once more, to verify it doesn't do anything for no changes
            logs[.null] = alwaysDoRedundancyCheck ? BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix) : nil

            // Check for unexpected build failures
            checkForNils(logs, allowableFailures: [.withError]).forEach {
                XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)")
            }
            
            // Check logs
            XCTAssert(logs[.initial]!.isNotNullBuild,                                       "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild)")
            XCTAssert(logs[.initial]! != logs[.withErrorFixed]!,                            "\(line()): \(IncBuildErrorMessages.fullBuildSameAsIncrementalBuild)")
            // There shouldn't be anything to build here, since we only edited
            // the Package.swift file
            XCTAssert(logs[.withErrorFixed]!.isNullBuild,                                   "\(line()): \(IncBuildErrorMessages.unexpectedBuild)")
            XCTAssert(logs[.initial]!.buildProducts == logs[.withErrorFixed]!.buildProducts,"\(line()): \(IncBuildErrorMessages.builtProductsDiffer)")
            // There shouldn't be anything for build 4 to do
            XCTAssert(logs[.null]?.isNullBuild ?? true,                                     "\(line()): \(IncBuildErrorMessages.unexpectedBuild)")
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
            logs[.initial] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            // remove the dependency
            try localFileSystem.writeFileContents(packagePath, bytes: packageNoDep.bytes)
            logs[.withoutDependency] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            // put it back
            try localFileSystem.writeFileContents(packagePath, bytes: packageDep.bytes)
            logs[.withDependency] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            // Once more, to verify it doesn't do anything for no changes
            logs[.null] = alwaysDoRedundancyCheck ? BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix) : nil
            
            // Check for unexpected build failures
            checkForNils(logs).forEach {
                XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)")
            }
            
            // Check the logs
            XCTAssert(logs[.initial]!.isNotNullBuild,                                       "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild)")
            // 1st rebuild... there's nothing actually using the dependency, so
            // this should be a null build
            XCTAssert(logs[.withoutDependency]!.isNullBuild,                                "\(line()): \(IncBuildErrorMessages.unexpectedBuild)")
            // 2nd rebuild... should still be a null build
            XCTAssert(logs[.withDependency]!.isNullBuild,                                   "\(line()): \(IncBuildErrorMessages.unexpectedBuild)")
            XCTAssert(logs[.initial]!.buildProducts == logs[.withDependency]!.buildProducts,"\(line()): \(IncBuildErrorMessages.builtProductsDiffer)")
            
            // There shouldn't be anything for build 4 to do
            XCTAssert(logs[.null]?.isNullBuild ?? true,                                     "\(line()): \(IncBuildErrorMessages.unexpectedBuild)")
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
            logs[.initial] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            // Remove a file and recompile
            localFileSystem.removeFileTree(extraFilePath)
            logs[.withoutFile] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            try localFileSystem.writeFileContents(extraFilePath, bytes: extraFile.bytes)
            // Put the file back and recompile
            logs[.withFile] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            // Once more, to verify it doesn't do anything for no changes
            logs[.null] = alwaysDoRedundancyCheck ? BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix) : nil
            
            // Check for unexpected build failures
            checkForNils(logs).forEach {
                XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)")
            }
            
            // Check logs
            XCTAssert(logs[.initial]!.isNotNullBuild,                                   "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild)")
            XCTAssert(logs[.withoutFile]!.isNotNullBuild,                               "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild)")
            XCTAssert(logs[.initial]! != logs[.withoutFile]!,                           "\(line()): \(IncBuildErrorMessages.unexpectedSimilar)")
            XCTAssert(logs[.withFile]!.isNotNullBuild,                                  "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild)")
            // The file that got removed contains an extension that overrides
            // the default implementation of something in a protocol, which is
            // only referenced from main.swift. AFAIK, that means that we should
            // only actually be compiling main.swift and FileTesterExt. If that's
            // not the case, these two build logs should be == insead of !=
            XCTAssert(logs[.initial]! != logs[.withFile]!,                              "\(line()): \(IncBuildErrorMessages.fullBuildSameAsIncrementalBuild)")
            XCTAssert(logs[.initial]!.buildProducts == logs[.withFile]!.buildProducts,  "\(line()): \(IncBuildErrorMessages.builtProductsDiffer)")
            // There shouldn't be anything for build 4 to do
            XCTAssert(logs[.null]?.isNullBuild ?? true,                                 "\(line()): \(IncBuildErrorMessages.unexpectedBuild)")
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
            logs[.initial] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            try localFileSystem.writeFileContents(packagePath, bytes: packageNoDep.bytes)
            logs[.withoutDependency] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            try localFileSystem.writeFileContents(packagePath, bytes: packageDep.bytes)
            logs[.withDependency] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            logs[.null] = alwaysDoRedundancyCheck ? BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix) : nil
            
            // Check for unexpected build failures
            checkForNils(logs).forEach {
                XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)")
            }
            
            var correctNum: Int
            // Check the logs
            XCTAssert(logs[.initial]!.isNotNullBuild,                                       "\(line()): \(IncBuildErrorMessages.unexpectedNullBuild)")
            XCTAssert(logs[.initial]! != logs[.withoutDependency]!,                         "\(line()): \(IncBuildErrorMessages.unexpectedSimilar)")
            // FIXME: Verify that this is actually correct
            correctNum = 1
            XCTAssert(logs[.withoutDependency]!.modules.count == correctNum,                "\(line()): \(Builds.withoutDependency) built \(logs[.withoutDependency]!.modules.count) modules instead of \(correctNum)")
            // FIXME: Verify that this is actually correct
            //correctNum is still 1
            XCTAssert(logs[.withDependency]!.modules.count == correctNum,                   "\(line()): \(Builds.withDependency) built \(logs[.withDependency]!.modules.count) modules instead of \(correctNum)")
            XCTAssert(logs[.initial]!.buildProducts == logs[.withDependency]!.buildProducts,"\(line()): \(IncBuildErrorMessages.builtProductsDiffer)")

            XCTAssert(logs[.null]?.isNullBuild ?? true,                                     "\(line()): \(IncBuildErrorMessages.unexpectedBuild)")
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
            
            logs[.initial] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            try localFileSystem.writeFileContents(packagePath, bytes: packageNoDep.bytes)
            logs[.withoutDependency] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            try localFileSystem.writeFileContents(packagePath, bytes: packageDep.bytes)
            logs[.withDependency] = BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix)
            logs[.null] = alwaysDoRedundancyCheck ? BuildResult(try? executeSwiftBuild(prefix, printIfError: true), path: prefix) : nil

            // Check for unexpected build failures
            checkForNils(logs).forEach {
                XCTFail("\(line()): \(IncBuildErrorMessages.unexpectedBuildFailure): \($0)")
            }
            
            // Check the logs

            // FIXME: Verify that this is actually correct
            var correctNum = 5
            XCTAssert(logs[.initial]!.modules.count == correctNum,                          "\(line()): \(Builds.initial) built \(logs[.initial]!.modules.count) binaries instead of \(correctNum)")
            // FIXME: Verify that this is actually correct
            correctNum = 2
            XCTAssert(logs[.initial]!.linkedBinaries.count == correctNum,                   "\(line()): \(Builds.initial) linked \(logs[.initial]!.linkedBinaries.count) binaries instead of \(correctNum)")
            
            // Removing a target doesn't need to recompile/rebuild anything, it
            // just removes a binary.
            // FIXME: Verify that this is actually correct
            correctNum = 0
            XCTAssert(logs[.withoutDependency]!.linkedBinaries.count == correctNum,         "\(line()): \(Builds.withoutDependency) linked \(logs[.withoutDependency]!.linkedBinaries.count) binaries instead of \(correctNum)")
            // FIXME: Verify that this is actually correct
            correctNum = 1
            XCTAssert(logs[.withoutDependency]!.modules.count == correctNum,                "\(line()): \(Builds.withoutDependency) built \(logs[.withoutDependency]!.modules.count) modules instead of \(correctNum))")
            
            // Adding the target back doesn't seem to do anything, either
            // FIXME: Verify that this is actually correct
            correctNum = 0
            XCTAssert(logs[.withDependency]!.linkedBinaries.count == correctNum,            "\(line()): \(Builds.withDependency) linked \(logs[.withDependency]!.linkedBinaries.count) binaries instead of \(correctNum)")
            // FIXME: Verify that this is actually correct
            correctNum = 1
            XCTAssert(logs[.withDependency]!.modules.count == correctNum,                   "\(line()): \(Builds.withDependency) built \(logs[.withDependency]!.modules.count) modules instead of \(correctNum)")
            XCTAssert(logs[.initial]!.buildProducts == logs[.withDependency]!.buildProducts,"\(line()): \(IncBuildErrorMessages.builtProductsDiffer)")
            XCTAssert(logs[.null]?.isNullBuild ?? true,                                     "\(line()): \(IncBuildErrorMessages.unexpectedBuild)")
        }
    }

    static var allTests = [
        ("testIncrementalSingleModuleCLibraryInSources",testIncrementalSingleModuleCLibraryInSources),
        ("testNullBuilds",                              testNullBuilds),
        ("testAddFixSourceCodeError",                   testAddFixSourceCodeError),
        ("testAddFixPackageError",                      testAddFixPackageError),
        ("testAddRemoveFiles",                          testAddRemoveFiles),
        ("testAddRemoveTargets",                        testAddRemoveTargets),
        ("testAddRemovePackageDependencies",            testAddRemovePackageDependencies),
        ("testAddRemoveTargetDependencies",             testAddRemoveTargetDependencies),
    ]
}
