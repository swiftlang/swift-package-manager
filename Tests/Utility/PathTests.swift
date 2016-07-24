/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import POSIX
import Utility

class PathTests: XCTestCase {

    func test() {
        XCTAssertEqual(Path.join("a","b","c","d"), "a/b/c/d")
        XCTAssertEqual(Path.join("/a","b","c","d"), "/a/b/c/d")

        XCTAssertEqual(Path.join("/", "a"), "/a")
        XCTAssertEqual(Path.join("//", "a"), "/a")
        XCTAssertEqual(Path.join("//", "//", "/", "///", "", "/", "//", "a"), "/a")
        XCTAssertEqual(Path.join("//", "//a//"), "/a")
        XCTAssertEqual(Path.join("/////"), "/")
    }

    func testPrecombined() {
        XCTAssertEqual(Path.join("a","b/c","d/"), "a/b/c/d")
        XCTAssertEqual(Path.join("a","b///c","d/"), "a/b/c/d")

        XCTAssertEqual(Path.join("/a","b/c","d/"), "/a/b/c/d")
        XCTAssertEqual(Path.join("/a","b///c","d/"), "/a/b/c/d")
    }

    func testExtraSeparators() {
        XCTAssertEqual(Path.join("a","b/","c/","d/"), "a/b/c/d")
        XCTAssertEqual(Path.join("/a","b/","c/","d/"), "/a/b/c/d")
    }

    func testEmpties() {
        XCTAssertEqual(Path.join("a","b/","","","c//","d/", ""), "a/b/c/d")
        XCTAssertEqual(Path.join("/a","b/","","","c//","d/", ""), "/a/b/c/d")
    }

    func testNormalizePath() {
        XCTAssertEqual("".normpath, ".")
        XCTAssertEqual("foo/../bar".normpath, "bar")
        XCTAssertEqual("foo///..///bar///baz".normpath, "bar/baz")
        XCTAssertEqual("foo/../bar/./".normpath, "bar")
        XCTAssertEqual("/".normpath, "/")
        XCTAssertEqual("////".normpath, "/")
        XCTAssertEqual("/abc/..".normpath, "/")
        XCTAssertEqual("/abc/def///".normpath, "/abc/def")
        XCTAssertEqual("../abc/def/".normpath, "../abc/def")
        XCTAssertEqual("../abc/../def/".normpath, "../def")
        XCTAssertEqual(".".normpath, ".")
        XCTAssertEqual("./././.".normpath, ".")
        XCTAssertEqual("./././../.".normpath, "..")

        // Only run tests using HOME if it is defined.
        if POSIX.getenv("HOME") != nil {
            XCTAssertEqual("~".normpath, Path.home)
            XCTAssertEqual("~abc".normpath, Path.join(Path.home, "..", "abc").normpath)
        }
    }

    func testJoinWithAbsoluteReturnsLastAbsoluteComponent() {
        XCTAssertEqual(Path.join("foo", "/abc/def"), "/abc/def")
    }

    func testParentDirectory() {
        XCTAssertEqual("foo/bar/baz".parentDirectory, "foo/bar")
        XCTAssertEqual("foo/bar/baz".parentDirectory.parentDirectory, "foo")
        XCTAssertEqual("/bar".parentDirectory, "/")
        XCTAssertEqual("/".parentDirectory, "/")
        XCTAssertEqual("/".parentDirectory.parentDirectory, "/")
        XCTAssertEqual("/bar/../foo/..//".parentDirectory.parentDirectory, "/")
    }

    static var allTests = [
        ("test", test),
        ("testPrecombined", testPrecombined),
        ("testExtraSeparators", testExtraSeparators),
        ("testEmpties", testEmpties),
        ("testNormalizePath", testNormalizePath),
        ("testJoinWithAbsoluteReturnsLastAbsoluteComponent", testJoinWithAbsoluteReturnsLastAbsoluteComponent),
        ("testParentDirectory", testParentDirectory),
    ]
}

class StatTests: XCTestCase {

    func test_isdir() {
        XCTAssertTrue(isDirectory("/usr"))
        XCTAssertTrue(isFile("/etc/passwd"))

        mktmpdir { root in
            try makeDirectories(root.appending("foo/bar"))
            try createSymlink(root.appending("symlink"), pointingAt: root.appending("foo"), relative: true)

            XCTAssertTrue(isDirectory(root.appending("foo/bar")))
            XCTAssertTrue(isDirectory(root.appending("symlink/bar")))
            XCTAssertTrue(isDirectory(root.appending("symlink")))
            XCTAssertTrue(isSymlink(root.appending("symlink")))

            try removeFileTree(root.appending("foo/bar"))
            try removeFileTree(root.appending("foo"))

            XCTAssertTrue(isSymlink(root.appending("symlink")))
            XCTAssertFalse(isDirectory(root.appending("symlink")))
            XCTAssertFalse(isFile(root.appending("symlink")))
        }
    }

    func test_isfile() {
        XCTAssertTrue(!isFile("/usr"))
        XCTAssertTrue(isFile("/etc/passwd"))
    }

    func test_realpath() {
        XCTAssertEqual(try! realpath("."), getcwd())
    }

    func test_basename() {
        XCTAssertEqual("base", "foo/bar/base".basename)
        XCTAssertEqual("base.ext", "foo/bar/base.ext".basename)
        XCTAssertNotEqual("bar", "foo/bar/base".basename)
        XCTAssertNotEqual("base.ext", "foo/bar/base".basename)
    }

    static var allTests = [
        ("test_isdir", test_isdir),
        ("test_isfile", test_isfile),
        ("test_realpath", test_realpath),
        ("test_basename", test_basename),
    ]
}

class RelativePathTests: XCTestCase {

    func testAbsolute() {
        XCTAssertEqual("2/3", Path("/1/2/3").relative(to: "/1/"))
        XCTAssertEqual("3/4", Path("/1/2////3/4///").relative(to: "////1//2//"))
    }

    func testRelative() {
        XCTAssertEqual("3/4", Path("1/2/3/4").relative(to: "1/2"))
    }

    func testMixed() {
        XCTAssertEqual("3/4", Path(getcwd() + "/1/2/3/4").relative(to: "1/2"))
    }
    
    func testRelativeCommonSubprefix() {
        XCTAssertEqual("../4", Path("/1/2/4").relative(to: "/1/2/3"))
        XCTAssertEqual("../4/5", Path("/1/2/4/5").relative(to: "/1/2/3"))
        XCTAssertEqual("../../../4/5", Path("/1/2/4/5").relative(to: "/1/2/3/6/7"))
    }
    
    func testCombiningRelativePaths() {
        XCTAssertEqual("/1/2/3", Path.join("/1/2/4", "../3").normpath)
        XCTAssertEqual("/1/2", Path.join("/1/2/3", "..").normpath)
        XCTAssertEqual("2", Path.join("2/3", "..").normpath)
    }

    static var allTests = [
        ("testAbsolute", testAbsolute),
        ("testRelative", testRelative),
        ("testMixed", testMixed),
        ("testRelativeCommonSubprefix", testRelativeCommonSubprefix),
        ("testCombiningRelativePaths", testCombiningRelativePaths)
    ]
}
