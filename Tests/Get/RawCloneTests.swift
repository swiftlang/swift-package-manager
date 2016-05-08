/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

@testable import Get
import struct PackageType.Manifest
import struct Utility.Path
import class PackageDescription.Package
import class Utility.Git
import func POSIX.popen
import XCTest


class GitTests: XCTestCase {
    func testHasVersion() {
        mktmpdir { path in
            let gitRepo = makeGitRepo(path, tag: "0.1.0")!
            XCTAssertTrue(gitRepo.hasVersion)
        }
    }

    func testHasNoVersion() {
        mktmpdir { path in
            let gitRepo = makeGitRepo(path, tag: nil)!
            XCTAssertFalse(gitRepo.hasVersion)
        }
    }

    func testCloneShouldNotCrashWihoutTags() {
        tryCloningRepoWithTag("0.1.0", shouldCrash: false)
    }

    func testCloneShouldCrashWihoutTags() {
        tryCloningRepoWithTag(nil, shouldCrash: true)
    }
}

//MARK: - Helpers

func makeGitRepo(_ dstdir: String, tag: String? = nil, file: StaticString = #file, line: UInt = #line) -> Git.Repo? {
    initGitRepo(dstdir, tag: tag)
    return Git.Repo(path: dstdir)
}

private func tryCloningRepoWithTag(_ tag: String?, shouldCrash: Bool) {
    var done = !shouldCrash
    mktmpdir { path in
        makeGitRepo(path, tag: tag)!
        do {
            _ = try RawClone(path: path, manifestParser: { _ throws in
                return Manifest(path: path, package: PackageDescription.Package(), products: [])
            })
        } catch Error.Unversioned {
            done = shouldCrash
        } catch {
            XCTFail()
        }
        XCTAssertTrue(done)
    }
}


extension VersionGraphTests {
    static var allTests : [(String, (VersionGraphTests) -> () throws -> Void)] {
        return [
            ("testNoGraph", testNoGraph),
            ("testOneDependency", testOneDependency),
            ("testOneDepenencyWithMultipleAvailableVersions", testOneDepenencyWithMultipleAvailableVersions),
            ("testOneDepenencyWithMultipleAvailableVersions", testOneDepenencyWithMultipleAvailableVersions),
            ("testTwoDependencies", testTwoDependencies),
            ("testTwoDirectDependencies", testTwoDirectDependencies),
            ("testTwoDirectDependenciesWhereOneAlsoDependsOnTheOther", testTwoDirectDependenciesWhereOneAlsoDependsOnTheOther),
            ("testSimpleVersionRestrictedGraph", testSimpleVersionRestrictedGraph),
            ("testComplexVersionRestrictedGraph", testComplexVersionRestrictedGraph),
            ("testVersionConstrain", testVersionConstrain),
            ("testTwoDependenciesRequireMutuallyExclusiveVersionsOfTheSameDependency_Simple", testTwoDependenciesRequireMutuallyExclusiveVersionsOfTheSameDependency_Simple),
            ("testTwoDependenciesRequireMutuallyExclusiveVersionsOfTheSameDependency_Complex", testTwoDependenciesRequireMutuallyExclusiveVersionsOfTheSameDependency_Complex),
            ("testVersionUnavailable", testVersionUnavailable)
        ]
    }
}

extension GetTests {
    static var allTests : [(String, (GetTests) -> () throws -> Void)] {
        return [
            ("testRawCloneDoesNotCrashIfManifestIsNotPresent", testRawCloneDoesNotCrashIfManifestIsNotPresent),
            ("testRangeConstrain", testRangeConstrain),
            ("testGitRepoInitialization", testGitRepoInitialization),
        ]
    }
}

extension GitTests {
    static var allTests : [(String, (GitTests) -> () throws -> Void)] {
        return [
            ("testHasVersion", testHasVersion),
            ("testHasNoVersion", testHasNoVersion),
            ("testCloneShouldNotCrashWihoutTags", testCloneShouldNotCrashWihoutTags),
            ("testCloneShouldCrashWihoutTags", testCloneShouldCrashWihoutTags),
        ]
    }
}
