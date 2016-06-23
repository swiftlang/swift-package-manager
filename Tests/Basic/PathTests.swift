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
        XCTAssertEqual(AbsolutePath("/").asString, "/")
        XCTAssertEqual(AbsolutePath("/a").asString, "/a")
        XCTAssertEqual(AbsolutePath("/a/b/c").asString, "/a/b/c")
        XCTAssertEqual(RelativePath(".").asString, ".")
        XCTAssertEqual(RelativePath("a").asString, "a")
        XCTAssertEqual(RelativePath("a/b/c").asString, "a/b/c")
    }
    
    func testRepeatedPathSeparators() {
        XCTAssertEqual(AbsolutePath("/ab//cd//ef").asString, "/ab/cd/ef")
        XCTAssertEqual(AbsolutePath("/ab///cd//ef").asString, "/ab/cd/ef")
        XCTAssertEqual(RelativePath("ab//cd//ef").asString, "ab/cd/ef")
        XCTAssertEqual(RelativePath("ab//cd///ef").asString, "ab/cd/ef")
    }
    
    func testTrailingPathSeparators() {
        XCTAssertEqual(AbsolutePath("/ab/cd/ef/").asString, "/ab/cd/ef")
        XCTAssertEqual(AbsolutePath("/ab/cd/ef//").asString, "/ab/cd/ef")
        XCTAssertEqual(RelativePath("ab/cd/ef/").asString, "ab/cd/ef")
        XCTAssertEqual(RelativePath("ab/cd/ef//").asString, "ab/cd/ef")
    }
    
    func testDotPathComponents() {
        XCTAssertEqual(AbsolutePath("/ab/././cd//ef").asString, "/ab/cd/ef")
        XCTAssertEqual(AbsolutePath("/ab/./cd//ef/.").asString, "/ab/cd/ef")
        XCTAssertEqual(RelativePath("ab/./cd/././ef").asString, "ab/cd/ef")
        XCTAssertEqual(RelativePath("ab/./cd/ef/.").asString, "ab/cd/ef")
    }
    
    func testDotDotPathComponents() {
        XCTAssertEqual(AbsolutePath("/..").asString, "/")
        XCTAssertEqual(AbsolutePath("/../../../../..").asString, "/")
        XCTAssertEqual(AbsolutePath("/abc/..").asString, "/")
        XCTAssertEqual(AbsolutePath("/abc/../..").asString, "/")
        XCTAssertEqual(AbsolutePath("/../abc").asString, "/abc")
        XCTAssertEqual(AbsolutePath("/../abc/..").asString, "/")
        XCTAssertEqual(AbsolutePath("/../abc/../def").asString, "/def")
        XCTAssertEqual(RelativePath("..").asString, "..")
        XCTAssertEqual(RelativePath("../..").asString, "../..")
        XCTAssertEqual(RelativePath(".././..").asString, "../..")
        XCTAssertEqual(RelativePath("../abc/..").asString, "..")
        XCTAssertEqual(RelativePath("../abc/.././").asString, "..")
        XCTAssertEqual(RelativePath("abc/..").asString, ".")
    }
    
    func testCombinationsAndEdgeCases() {
        XCTAssertEqual(AbsolutePath("///").asString, "/")
        XCTAssertEqual(AbsolutePath("/./").asString, "/")
        XCTAssertEqual(RelativePath("").asString, ".")
        XCTAssertEqual(RelativePath(".").asString, ".")
        XCTAssertEqual(RelativePath("./abc").asString, "abc")
        XCTAssertEqual(RelativePath("./abc/").asString, "abc")
        XCTAssertEqual(RelativePath("./abc/../bar").asString, "bar")
        XCTAssertEqual(RelativePath("foo/../bar").asString, "bar")
        XCTAssertEqual(RelativePath("foo///..///bar///baz").asString, "bar/baz")
        XCTAssertEqual(RelativePath("foo/../bar/./").asString, "bar")
        XCTAssertEqual(RelativePath("../abc/def/").asString, "../abc/def")
        XCTAssertEqual(RelativePath("././././.").asString, ".")
        XCTAssertEqual(RelativePath("./././../.").asString, "..")
        XCTAssertEqual(RelativePath("./").asString, ".")
        XCTAssertEqual(RelativePath(".//").asString, ".")
        XCTAssertEqual(RelativePath("./.").asString, ".")
        XCTAssertEqual(RelativePath("././").asString, ".")
        XCTAssertEqual(RelativePath("../").asString, "..")
        XCTAssertEqual(RelativePath("../.").asString, "..")
        XCTAssertEqual(RelativePath("./..").asString, "..")
        XCTAssertEqual(RelativePath("./../.").asString, "..")
        XCTAssertEqual(RelativePath("./////../////./////").asString, "..")
        XCTAssertEqual(RelativePath("../a").asString, "../a")
        XCTAssertEqual(RelativePath("../a/..").asString, "..")
        XCTAssertEqual(RelativePath("a/..").asString, ".")
        XCTAssertEqual(RelativePath("a/../////../////./////").asString, "..")
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
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), RelativePath("")).asString, "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), RelativePath(".")).asString, "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), RelativePath("..")).asString, "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), RelativePath("bar")).asString, "/bar")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/foo/bar"), RelativePath("..")).asString, "/foo")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/bar"), RelativePath("../foo")).asString, "/foo")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/bar"), RelativePath("../foo/..//")).asString, "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/bar/../foo/..//yabba/"), RelativePath("a/b")).asString, "/yabba/a/b")
        
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), "").asString, "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), ".").asString, "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), "..").asString, "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), "bar").asString, "/bar")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/foo/bar"), "..").asString, "/foo")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/bar"), "../foo").asString, "/foo")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/bar"), "../foo/..//").asString, "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/bar/../foo/..//yabba/"), "a/b").asString, "/yabba/a/b")
    }
    
    // FIXME: We also need tests for join() operations.
    
    // FIXME: We also need tests for dirname, basename, suffix, etc.
    
    // FIXME: We also need test for stat() operations.
        
    static var allTests = [
        ("testBasics",                   testBasics),
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
