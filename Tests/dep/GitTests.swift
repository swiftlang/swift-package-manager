/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */
import XCTest
import XCTestCaseProvider

import struct sys.Path
@testable import dep
import func POSIX.popen

class GitTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () throws -> Void)] {
        return [
            ("testHasVersion", testHasVersion),
            ("testHasNoVersion", testHasNoVersion),
            ("testCloneShouldNotCrashWihoutTags", testCloneShouldNotCrashWihoutTags),
            ("testCloneShouldCrashWihoutTags", testCloneShouldCrashWihoutTags),

        ]
    }

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

private func makeGitRepo(dstdir: String, tag: String?, file: StaticString = #file, line: UInt = #line) -> Git.Repo? {
    do {
        let file = Path.join(dstdir, "file.swift")
        try popen(["touch", file])
        try popen(["git", "-C", dstdir, "init"])
        try popen(["git", "-C", dstdir, "config", "user.email", "example@example.com"])
        try popen(["git", "-C", dstdir, "config", "user.name", "Example Example"])
        try popen(["git", "-C", dstdir, "add", "."])
        try popen(["git", "-C", dstdir, "commit", "-m", "msg"])
        if let tag = tag {
            try popen(["git", "-C", dstdir, "tag", tag])
        }
        return Git.Repo(root: dstdir)
    }
    catch {
        XCTFail(safeStringify(error), file: file, line: line)
    }
    return nil
}

private func tryCloningRepoWithTag(tag: String?, shouldCrash: Bool) {
    var done = !shouldCrash
    mktmpdir { path in
        makeGitRepo(path, tag: tag)!
        do {
            _ = try Sandbox.RawClone(path: path)
        } catch Error.GitVersionTagRequired {
            done = shouldCrash
        } catch {
            XCTFail()
        }
        XCTAssertTrue(done)
    }
}
