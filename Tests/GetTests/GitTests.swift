/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

import Basic
import Utility

import TestSupport

import class PackageDescription.Package
import struct PackageModel.Manifest

@testable import Get

class GitTests: XCTestCase {
    func testHasVersion() {
        mktmpdir { path in
            let gitRepo = makeGitRepo(path, tag: "0.1.0")!
            XCTAssertTrue(gitRepo.hasVersion)
            XCTAssertEqual(gitRepo.versions, [Version(0,1,0)])
        }
        mktmpdir { path in
            let gitRepo = makeGitRepo(path, tag: "v0.1.0")!
            XCTAssertTrue(gitRepo.hasVersion)
            XCTAssertEqual(gitRepo.versions, [Version(0,1,0)])
        }
    }

    func testVersionSpecificTags() {
        let current = Versioning.currentVersion
        mktmpdir { path in
            let gitRepo = makeGitRepo(path, tags: ["0.1.0", "0.2.0@swift-\(current.major)", "0.3.0@swift-\(current.major).\(current.minor)", "0.4.0@swift-\(current.major).\(current.minor).\(current.patch)"])!
            XCTAssertTrue(gitRepo.hasVersion)
            XCTAssertEqual(gitRepo.versions, [Version(0,4,0)])
        }
        mktmpdir { path in
            let gitRepo = makeGitRepo(path, tags: ["0.1.0", "0.2.0@swift-\(current.major)", "0.3.0@swift-\(current.major).\(current.minor)"])!
            XCTAssertTrue(gitRepo.hasVersion)
            XCTAssertEqual(gitRepo.versions, [Version(0,3,0)])
        }
        mktmpdir { path in
            let gitRepo = makeGitRepo(path, tags: ["0.1.0", "0.2.0@swift-\(current.major)"])!
            XCTAssertTrue(gitRepo.hasVersion)
            XCTAssertEqual(gitRepo.versions, [Version(0,2,0)])
        }
        mktmpdir { path in
            let gitRepo = makeGitRepo(path, tags: ["0.1.0", "v0.2.0@swift-\(current.major)"])!
            XCTAssertTrue(gitRepo.hasVersion)
            XCTAssertEqual(gitRepo.versions, [Version(0,2,0)])
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

    static var allTests = [
        ("testHasVersion", testHasVersion),
        ("testVersionSpecificTags", testVersionSpecificTags),
        ("testHasNoVersion", testHasNoVersion),
        ("testCloneShouldNotCrashWihoutTags", testCloneShouldNotCrashWihoutTags),
        ("testCloneShouldCrashWihoutTags", testCloneShouldCrashWihoutTags),
    ]
}

//MARK: - Helpers

func makeGitRepo(_ dstdir: AbsolutePath, tag: String? = nil, file: StaticString = #file, line: UInt = #line) -> Git.Repo? {
    return makeGitRepo(dstdir, tags: tag.flatMap{ [$0] } ?? [], file: file, line: line)
}

func makeGitRepo(_ dstdir: AbsolutePath, tags: [String], file: StaticString = #file, line: UInt = #line) -> Git.Repo? {
    initGitRepo(dstdir, tags: tags)
    return Git.Repo(path: dstdir)
}

private func tryCloningRepoWithTag(_ tag: String?, shouldCrash: Bool) {
    var done = !shouldCrash
    mktmpdir { path in
        _ = makeGitRepo(path, tag: tag)!
        do {
            _ = try RawClone(path: path, manifestParser: { _ throws in
                return Manifest(path: path, url: path.asString, package: PackageDescription.Package(name: path.basename), products: [], version: nil)
            })
        } catch Get.Error.unversioned {
            done = shouldCrash
        } catch {
            XCTFail()
        }
        XCTAssertTrue(done)
    }
}
