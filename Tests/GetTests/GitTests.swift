/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import XCTest

import Basic
@testable import Get
import struct PackageModel.Manifest
import class PackageDescription.Package
import class Utility.Git

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

    static var allTests = [
        ("testHasVersion", testHasVersion),
        ("testHasNoVersion", testHasNoVersion),
        ("testCloneShouldNotCrashWihoutTags", testCloneShouldNotCrashWihoutTags),
        ("testCloneShouldCrashWihoutTags", testCloneShouldCrashWihoutTags),
    ]
}

//MARK: - Helpers

func makeGitRepo(_ dstdir: AbsolutePath, tag: String? = nil, file: StaticString = #file, line: UInt = #line) -> Git.Repo? {
    initGitRepo(dstdir, tag: tag)
    return Git.Repo(path: dstdir)
}

private func tryCloningRepoWithTag(_ tag: String?, shouldCrash: Bool) {
    var done = !shouldCrash
    mktmpdir { path in
        _ = makeGitRepo(path, tag: tag)!
        do {
            _ = try RawClone(path: path, manifestParser: { _, _, _ throws in
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
