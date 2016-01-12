//
//  GitTests.swift
//  swiftpm
//
//  Created by Kostiantyn Koval on 09/01/16.
//  Copyright © 2016 Apple, Inc. All rights reserved.
//

import XCTest
import XCTestCaseProvider

import struct sys.Path
@testable import dep
import func POSIX.popen

class GitTests: XCTestCase, XCTestCaseProvider {

    var allTests : [(String, () -> Void)] {
        return [
            ("testHasVersion", testHasVersion),
            ("testHasNoVersion", testHasNoVersion),
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
}

//MARK: - Helpers

private func makeGitRepo(dstdir: String, tag: String?, file: StaticString = __FILE__, line: UInt = __LINE__) -> Git.Repo? {
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
