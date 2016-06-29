/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import POSIX
import Basic
import Utility


class PathTests: XCTestCase {
    
    func testBasics() {
        XCTAssertEqual(String(AbsolutePath("/")), "/")
        XCTAssertEqual(String(AbsolutePath("/a")), "/a")
        XCTAssertEqual(String(AbsolutePath("/a/b/c")), "/a/b/c")
        XCTAssertEqual(String(RelativePath(".")), ".")
        XCTAssertEqual(String(RelativePath("a")), "a")
        XCTAssertEqual(String(RelativePath("a/b/c")), "a/b/c")
    }
    
    func testStringLiteralInitialization() {
        let abs: AbsolutePath = "/"
        XCTAssertEqual(String(abs), "/")
        let rel: RelativePath = "."
        XCTAssertEqual(String(rel), ".")
    }
    
    func testRepeatedPathSeparators() {
        XCTAssertEqual(String(AbsolutePath("/ab//cd//ef")), "/ab/cd/ef")
        XCTAssertEqual(String(AbsolutePath("/ab///cd//ef")), "/ab/cd/ef")
        XCTAssertEqual(String(RelativePath("ab//cd//ef")), "ab/cd/ef")
        XCTAssertEqual(String(RelativePath("ab//cd///ef")), "ab/cd/ef")
    }
    
    func testTrailingPathSeparators() {
        XCTAssertEqual(String(AbsolutePath("/ab/cd/ef/")), "/ab/cd/ef")
        XCTAssertEqual(String(AbsolutePath("/ab/cd/ef//")), "/ab/cd/ef")
        XCTAssertEqual(String(RelativePath("ab/cd/ef/")), "ab/cd/ef")
        XCTAssertEqual(String(RelativePath("ab/cd/ef//")), "ab/cd/ef")
    }
    
    func testDotPathComponents() {
        XCTAssertEqual(String(AbsolutePath("/ab/././cd//ef")), "/ab/cd/ef")
        XCTAssertEqual(String(AbsolutePath("/ab/./cd//ef/.")), "/ab/cd/ef")
        XCTAssertEqual(String(RelativePath("ab/./cd/././ef")), "ab/cd/ef")
        XCTAssertEqual(String(RelativePath("ab/./cd/ef/.")), "ab/cd/ef")
    }
    
    func testDotDotPathComponents() {
        XCTAssertEqual(String(AbsolutePath("/..")), "/")
        XCTAssertEqual(String(AbsolutePath("/../../../../..")), "/")
        XCTAssertEqual(String(AbsolutePath("/abc/..")), "/")
        XCTAssertEqual(String(AbsolutePath("/abc/../..")), "/")
        XCTAssertEqual(String(AbsolutePath("/../abc")), "/abc")
        XCTAssertEqual(String(AbsolutePath("/../abc/..")), "/")
        XCTAssertEqual(String(AbsolutePath("/../abc/../def")), "/def")
        XCTAssertEqual(String(RelativePath("..")), "..")
        XCTAssertEqual(String(RelativePath("../..")), "../..")
        XCTAssertEqual(String(RelativePath(".././..")), "../..")
        XCTAssertEqual(String(RelativePath("../abc/..")), "..")
        XCTAssertEqual(String(RelativePath("../abc/.././")), "..")
        XCTAssertEqual(String(RelativePath("abc/..")), ".")
    }
    
    func testCombinationsAndEdgeCases() {
        XCTAssertEqual(String(AbsolutePath("///")), "/")
        XCTAssertEqual(String(AbsolutePath("/./")), "/")
        XCTAssertEqual(String(RelativePath("")), ".")
        XCTAssertEqual(String(RelativePath(".")), ".")
        XCTAssertEqual(String(RelativePath("./abc")), "abc")
        XCTAssertEqual(String(RelativePath("./abc/")), "abc")
        XCTAssertEqual(String(RelativePath("./abc/../bar")), "bar")
        XCTAssertEqual(String(RelativePath("foo/../bar")), "bar")
        XCTAssertEqual(String(RelativePath("foo///..///bar///baz")), "bar/baz")
        XCTAssertEqual(String(RelativePath("foo/../bar/./")), "bar")
        XCTAssertEqual(String(RelativePath("../abc/def/")), "../abc/def")
        XCTAssertEqual(String(RelativePath("././././.")), ".")
        XCTAssertEqual(String(RelativePath("./././../.")), "..")
        XCTAssertEqual(String(RelativePath("./")), ".")
        XCTAssertEqual(String(RelativePath(".//")), ".")
        XCTAssertEqual(String(RelativePath("./.")), ".")
        XCTAssertEqual(String(RelativePath("././")), ".")
        XCTAssertEqual(String(RelativePath("../")), "..")
        XCTAssertEqual(String(RelativePath("../.")), "..")
        XCTAssertEqual(String(RelativePath("./..")), "..")
        XCTAssertEqual(String(RelativePath("./../.")), "..")
        XCTAssertEqual(String(RelativePath("./////../////./////")), "..")
        XCTAssertEqual(String(RelativePath("../a")), "../a")
        XCTAssertEqual(String(RelativePath("../a/..")), "..")
        XCTAssertEqual(String(RelativePath("a/..")), ".")
        XCTAssertEqual(String(RelativePath("a/../////../////./////")), "..")
    }
        
    func testDirectoryNameExtraction() {
        XCTAssertEqual(AbsolutePath("/").dirname, "/")
        XCTAssertEqual(AbsolutePath("/a").dirname, "/")
        XCTAssertEqual(AbsolutePath("/./a").dirname, "/")
        XCTAssertEqual(AbsolutePath("/../..").dirname, "/")
        XCTAssertEqual(AbsolutePath("/ab/c//d/").dirname, "/ab/c")
        XCTAssertEqual(RelativePath("ab/c//d/").dirname, "ab/c")
        XCTAssertEqual(RelativePath("../a").dirname, "..")
        XCTAssertEqual(RelativePath("../a/..").dirname, ".")
        XCTAssertEqual(RelativePath("a/..").dirname, ".")
        XCTAssertEqual(RelativePath("./..").dirname, ".")
        XCTAssertEqual(RelativePath("a/../////../////./////").dirname, ".")
        XCTAssertEqual(RelativePath("abc").dirname, ".")
        XCTAssertEqual(RelativePath("").dirname, ".")
        XCTAssertEqual(RelativePath(".").dirname, ".")
    }
    
    func testBaseNameExtraction() {
        XCTAssertEqual(AbsolutePath("/").basename, "/")
        XCTAssertEqual(AbsolutePath("/a").basename, "a")
        XCTAssertEqual(AbsolutePath("/./a").basename, "a")
        XCTAssertEqual(AbsolutePath("/../..").basename, "/")
        XCTAssertEqual(RelativePath("../..").basename, "..")
        XCTAssertEqual(RelativePath("../a").basename, "a")
        XCTAssertEqual(RelativePath("../a/..").basename, "..")
        XCTAssertEqual(RelativePath("a/..").basename, ".")
        XCTAssertEqual(RelativePath("./..").basename, "..")
        XCTAssertEqual(RelativePath("a/../////../////./////").basename, "..")
        XCTAssertEqual(RelativePath("abc").basename, "abc")
        XCTAssertEqual(RelativePath("").basename, ".")
        XCTAssertEqual(RelativePath(".").basename, ".")
    }
    
    func testSuffixExtraction() {
        XCTAssertEqual(RelativePath("a").suffix, nil)
        XCTAssertEqual(RelativePath("a.").suffix, nil)
        XCTAssertEqual(RelativePath(".a").suffix, nil)
        XCTAssertEqual(RelativePath("").suffix, nil)
        XCTAssertEqual(RelativePath(".").suffix, nil)
        XCTAssertEqual(RelativePath("..").suffix, nil)
        XCTAssertEqual(RelativePath("a.foo").suffix, ".foo")
        XCTAssertEqual(RelativePath(".a.foo").suffix, ".foo")
        XCTAssertEqual(RelativePath(".a.foo.bar").suffix, ".bar")
        XCTAssertEqual(RelativePath("a.foo.bar").suffix, ".bar")
        XCTAssertEqual(RelativePath(".a.foo.bar.baz").suffix, ".baz")
    }
    
    func testParentDirectory() {
        XCTAssertEqual(AbsolutePath("/").parentDirectory, AbsolutePath("/"))
        XCTAssertEqual(AbsolutePath("/").parentDirectory.parentDirectory, AbsolutePath("/"))
        XCTAssertEqual(AbsolutePath("/bar").parentDirectory, AbsolutePath("/"))
        XCTAssertEqual(AbsolutePath("/bar/../foo/..//").parentDirectory.parentDirectory, AbsolutePath("/"))
        XCTAssertEqual(AbsolutePath("/bar/../foo/..//yabba/a/b").parentDirectory.parentDirectory, AbsolutePath("/yabba"))
    }
    
    func testConcatenation() {
        XCTAssertEqual(String(AbsolutePath(AbsolutePath("/"), RelativePath(""))), "/")
        XCTAssertEqual(String(AbsolutePath(AbsolutePath("/"), RelativePath("."))), "/")
        XCTAssertEqual(String(AbsolutePath(AbsolutePath("/"), RelativePath(".."))), "/")
        XCTAssertEqual(String(AbsolutePath(AbsolutePath("/"), RelativePath("bar"))), "/bar")
        XCTAssertEqual(String(AbsolutePath(AbsolutePath("/foo/bar"), RelativePath(".."))), "/foo")
        XCTAssertEqual(String(AbsolutePath(AbsolutePath("/bar"), RelativePath("../foo"))), "/foo")
        XCTAssertEqual(String(AbsolutePath(AbsolutePath("/bar"), RelativePath("../foo/..//"))), "/")
        XCTAssertEqual(String(AbsolutePath(AbsolutePath("/bar/../foo/..//yabba/"), RelativePath("a/b"))), "/yabba/a/b")
        
        XCTAssertEqual(String(AbsolutePath("/").appending(RelativePath(""))), "/")
        XCTAssertEqual(String(AbsolutePath("/").appending(RelativePath("."))), "/")
        XCTAssertEqual(String(AbsolutePath("/").appending(RelativePath(".."))), "/")
        XCTAssertEqual(String(AbsolutePath("/").appending(RelativePath("bar"))), "/bar")
        XCTAssertEqual(String(AbsolutePath("/foo/bar").appending(RelativePath(".."))), "/foo")
        XCTAssertEqual(String(AbsolutePath("/bar").appending(RelativePath("../foo"))), "/foo")
        XCTAssertEqual(String(AbsolutePath("/bar").appending(RelativePath("../foo/..//"))), "/")
        XCTAssertEqual(String(AbsolutePath("/bar/../foo/..//yabba/").appending(RelativePath("a/b"))), "/yabba/a/b")
    }
    
    func testPathComponents() {
        XCTAssertEqual(AbsolutePath("/").components, ["/"])
        XCTAssertEqual(AbsolutePath("/.").components, ["/"])
        XCTAssertEqual(AbsolutePath("/..").components, ["/"])
        XCTAssertEqual(AbsolutePath("/bar").components, ["/", "bar"])
        XCTAssertEqual(AbsolutePath("/foo/bar/..").components, ["/", "foo"])
        XCTAssertEqual(AbsolutePath("/bar/../foo").components, ["/", "foo"])
        XCTAssertEqual(AbsolutePath("/bar/../foo/..//").components, ["/"])
        XCTAssertEqual(AbsolutePath("/bar/../foo/..//yabba/a/b/").components, ["/", "yabba", "a", "b"])
        
        XCTAssertEqual(RelativePath("").components, ["."])
        XCTAssertEqual(RelativePath(".").components, ["."])
        XCTAssertEqual(RelativePath("..").components, [".."])
        XCTAssertEqual(RelativePath("bar").components, ["bar"])
        XCTAssertEqual(RelativePath("foo/bar/..").components, ["foo"])
        XCTAssertEqual(RelativePath("bar/../foo").components, ["foo"])
        XCTAssertEqual(RelativePath("bar/../foo/..//").components, ["."])
        XCTAssertEqual(RelativePath("bar/../foo/..//yabba/a/b/").components, ["yabba", "a", "b"])
        XCTAssertEqual(RelativePath("../..").components, ["..", ".."])
        XCTAssertEqual(RelativePath(".././/..").components, ["..", ".."])
        XCTAssertEqual(RelativePath("../a").components, ["..", "a"])
        XCTAssertEqual(RelativePath("../a/..").components, [".."])
        XCTAssertEqual(RelativePath("a/..").components, ["."])
        XCTAssertEqual(RelativePath("./..").components, [".."])
        XCTAssertEqual(RelativePath("a/../////../////./////").components, [".."])
        XCTAssertEqual(RelativePath("abc").components, ["abc"])
    }
    
    func testRelativePathFromAbsolutePaths() {
        XCTAssertEqual(AbsolutePath("/").relative(to: AbsolutePath("/")), RelativePath("."));
        XCTAssertEqual(AbsolutePath("/a/b/c/d").relative(to: AbsolutePath("/")), RelativePath("a/b/c/d"));
        XCTAssertEqual(AbsolutePath("/").relative(to: AbsolutePath("/a/b/c")), RelativePath("../../.."));
        XCTAssertEqual(AbsolutePath("/a/b/c/d").relative(to: AbsolutePath("/a/b")), RelativePath("c/d"));
        XCTAssertEqual(AbsolutePath("/a/b/c/d").relative(to: AbsolutePath("/a/b/c")), RelativePath("d"));
        XCTAssertEqual(AbsolutePath("/a/b/c/d").relative(to: AbsolutePath("/a/c/d")), RelativePath("../../b/c/d"));
        XCTAssertEqual(AbsolutePath("/a/b/c/d").relative(to: AbsolutePath("/b/c/d")), RelativePath("../../../a/b/c/d"));
    }
    
    // FIXME: We also need tests for join() operations.
    
    // FIXME: We also need tests for dirname, basename, suffix, etc.
    
    // FIXME: We also need test for stat() operations.
        
    static var allTests = [
        ("testBasics",                   testBasics),
        ("testStringLiteralInitialization", testStringLiteralInitialization),
        ("testRepeatedPathSeparators",   testRepeatedPathSeparators),
        ("testTrailingPathSeparators",   testTrailingPathSeparators),
        ("testDotPathComponents",        testDotPathComponents),
        ("testDotDotPathComponents",     testDotDotPathComponents),
        ("testCombinationsAndEdgeCases", testCombinationsAndEdgeCases),
        ("testBaseNameExtraction",       testBaseNameExtraction),
        ("testSuffixExtraction",         testSuffixExtraction),
        ("testParentDirectory",          testParentDirectory),
        ("testConcatenation",            testConcatenation),
    ]
}
