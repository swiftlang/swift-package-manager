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

class WalkTests: XCTestCase {

    func testNonRecursive() {
        var expected: [AbsolutePath] = [ "/usr", "/bin", "/sbin" ]

        for x in walk("/", recursively: false) {
            if let i = expected.index(of: x) {
                expected.remove(at: i)
            }
            XCTAssertEqual(2, x.components.count)
        }

        XCTAssertEqual(expected.count, 0)
    }

    func testRecursive() {
        let root = AbsolutePath(#file).appending("../../../Sources")
        var expected: [AbsolutePath] = [ root.appending("Build"), root.appending("Utility") ]

        for x in walk(root) {
            if let i = expected.index(of: x) {
                expected.remove(at: i)
            }
        }

        XCTAssertEqual(expected.count, 0)
    }

    func testSymlinksNotWalked() {
        mktmpdir { root in
            let root = resolveSymlinks(root)  // FIXME: it would be better to not need this, but we end up relying on /tmp -> /private/tmp.
            
            try makeDirectories(root.appending("foo"))
            try makeDirectories(root.appending("bar/baz/goo"))
            try symlink(create: root.appending("foo/symlink").asString, pointingAt: root.appending("bar").asString, relativeTo: root.asString)

            XCTAssertTrue(root.appending("foo/symlink").asString.isSymlink)
            XCTAssertEqual(resolveSymlinks(root.appending("foo/symlink")), root.appending("bar"))
            XCTAssertTrue(resolveSymlinks(root.appending("foo/symlink/baz")).asString.isDirectory)

            let results = walk(root.appending("foo")).map{ $0 }

            XCTAssertEqual(results, [root.appending("foo/symlink")])
        }
    }

    func testWalkingADirectorySymlinkResolvesOnce() {
        mktmpdir { root in
            try makeDirectories(root.appending("foo/bar"))
            try makeDirectories(root.appending("abc/bar"))
            try symlink(create: root.appending("symlink").asString, pointingAt: root.appending("foo").asString, relativeTo: root.asString)
            try symlink(create: root.appending("foo/baz").asString, pointingAt: root.appending("abc").asString, relativeTo: root.asString)

            XCTAssertTrue(root.appending("symlink").asString.isSymlink)

            let results = walk(root.appending("symlink")).map{ $0 }.sorted()

            // we recurse a symlink to a directory, so this should work,
            // but `abc` should not show because `baz` is a symlink too
            // and that should *not* be followed

            XCTAssertEqual(results, [root.appending("symlink/bar"), root.appending("symlink/baz")])
        }
    }
}

extension WalkTests {
    static var allTests = [
        ("testNonRecursive", testNonRecursive),
        ("testRecursive", testRecursive),
        ("testSymlinksNotWalked", testSymlinksNotWalked),
        ("testWalkingADirectorySymlinkResolvesOnce", testWalkingADirectorySymlinkResolvesOnce),
    ]
}

class StatTests: XCTestCase {

    func test_isdir() {
        XCTAssertTrue("/usr".isDirectory)
        XCTAssertTrue("/etc/passwd".isFile)

        mktmpdir { root in
            try makeDirectories(root.appending("foo/bar"))
            try symlink(create: root.appending("symlink").asString, pointingAt: root.appending("foo").asString, relativeTo: root.asString)

            XCTAssertTrue(root.appending("foo/bar").asString.isDirectory)
            XCTAssertTrue(root.appending("symlink/bar").asString.isDirectory)
            XCTAssertTrue(root.appending("symlink").asString.isDirectory)
            XCTAssertTrue(root.appending("symlink").asString.isSymlink)

            try removeFileTree(root.appending("foo/bar"))
            try removeFileTree(root.appending("foo"))

            XCTAssertTrue(root.appending("symlink").asString.isSymlink)
            XCTAssertFalse(root.appending("symlink").asString.isDirectory)
            XCTAssertFalse(root.appending("symlink").asString.isFile)
        }
    }

    func test_isfile() {
        XCTAssertTrue(!"/usr".isFile)
        XCTAssertTrue("/etc/passwd".isFile)
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
