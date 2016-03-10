/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Utility
import XCTest
import POSIX

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
        XCTAssertEqual("/".parentDirectory.parentDirectory, "/")
        XCTAssertEqual("/bar/../foo/..//".parentDirectory.parentDirectory, "/")
    }
}

class WalkTests: XCTestCase {

    func testNonRecursive() {
        var expected = ["/usr", "/bin", "/sbin"]

        for x in walk("/", recursively: false) {
            if let i = expected.index(of: x) {
                expected.remove(at: i)
            }
            XCTAssertEqual(1, x.characters.split(separator: "/").count)
        }

        XCTAssertEqual(expected.count, 0)
    }

    func testRecursive() {
        let root = Path.join(#file, "../../../Sources").normpath
        var expected = [
            Path.join(root, "Build"),
            Path.join(root, "Utility")
        ]

        for x in walk(root) {
            if let i = expected.index(of: x) {
                expected.remove(at: i)
            }
        }

        XCTAssertEqual(expected.count, 0)
    }

    func testSymlinksNotWalked() {
        do {
            try mkdtemp("foo") { root in
                let root = try realpath(root)  //FIXME not good that we need this?

                try mkdir(root, "foo")
                try mkdir(root, "bar/baz/goo")
                try symlink(create: "\(root)/foo/symlink", pointingAt: "\(root)/bar", relativeTo: root)

                XCTAssertTrue("\(root)/foo/symlink".isSymlink)
                XCTAssertEqual(try! realpath("\(root)/foo/symlink"), "\(root)/bar")
                XCTAssertTrue(try! realpath("\(root)/foo/symlink/baz").isDirectory)


                let results = walk(root, "foo").map{$0}

                XCTAssertEqual(results, ["\(root)/foo/symlink"])
            }
        } catch {
            XCTFail("\(error)")
        }
    }

    func testWalkingADirectorySymlinkResolvesOnce() {
        try! mkdtemp("foo") { root in
            let root = try realpath(root)  //FIXME not good that we need this?

            try mkdir(root, "foo/bar")
            try mkdir(root, "abc/bar")
            try symlink(create: "\(root)/symlink", pointingAt: "\(root)/foo", relativeTo: root)
            try symlink(create: "\(root)/foo/baz", pointingAt: "\(root)/abc", relativeTo: root)

            XCTAssertTrue(Path.join(root, "symlink").isSymlink)

            let results = walk(root, "symlink").map{$0}.sorted()

            // we recurse a symlink to a directory, so this should work,
            // but `abc` should not show because `baz` is a symlink too
            // and that should *not* be followed

            XCTAssertEqual(results, ["\(root)/symlink/bar", "\(root)/symlink/baz"])
        }
    }
}

class StatTests: XCTestCase {

    func test_isdir() {
        XCTAssertTrue("/usr".isDirectory)
        XCTAssertTrue("/etc/passwd".isFile)

        try! mkdtemp("foo") { root in
            try mkdir(root, "foo/bar")
            try symlink(create: "\(root)/symlink", pointingAt: "\(root)/foo", relativeTo: root)

            XCTAssertTrue("\(root)/foo/bar".isDirectory)
            XCTAssertTrue("\(root)/symlink/bar".isDirectory)
            XCTAssertTrue("\(root)/symlink".isDirectory)
            XCTAssertTrue("\(root)/symlink".isSymlink)

            try POSIX.rmdir("\(root)/foo/bar")
            try POSIX.rmdir("\(root)/foo")

            XCTAssertTrue("\(root)/symlink".isSymlink)
            XCTAssertFalse("\(root)/symlink".isDirectory)
            XCTAssertFalse("\(root)/symlink".isFile)
        }
    }

    func test_isfile() {
        XCTAssertTrue(!"/usr".isFile)
        XCTAssertTrue("/etc/passwd".isFile)
    }

    func test_realpath() {
        XCTAssertEqual(try! realpath("."), try! getcwd())
    }

    func test_basename() {
        XCTAssertEqual("base", "foo/bar/base".basename)
        XCTAssertEqual("base.ext", "foo/bar/base.ext".basename)
        XCTAssertNotEqual("bar", "foo/bar/base".basename)
        XCTAssertNotEqual("base.ext", "foo/bar/base".basename)
    }
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
        XCTAssertEqual("3/4", Path(try! getcwd() + "/1/2/3/4").relative(to: "1/2"))
    }
}
