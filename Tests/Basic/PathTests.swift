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
        
    func testBaseNameExtraction() {
        XCTAssertEqual(AbsolutePath("/a").basename, "a")
        XCTAssertEqual(AbsolutePath("/./a").basename, "a")
        XCTAssertEqual(AbsolutePath("/../..").basename, "/")
        XCTAssertEqual(RelativePath("../..").basename, "..")
        XCTAssertEqual(RelativePath("../a").basename, "a")
        XCTAssertEqual(RelativePath("../a/..").basename, "..")
        XCTAssertEqual(RelativePath("a/..").basename, ".")
        XCTAssertEqual(RelativePath("./..").basename, "..")
        XCTAssertEqual(RelativePath("a/..").basename, ".")
        XCTAssertEqual(RelativePath("a/../////../////./////").basename, "..")
        XCTAssertEqual(RelativePath("abc").basename, "abc")
        XCTAssertEqual(RelativePath("").basename, ".")
    }
    
    func testSuffixExtraction() {
        XCTAssertEqual(RelativePath("a").suffix, nil)
        XCTAssertEqual(RelativePath("a.").suffix, nil)
        XCTAssertEqual(RelativePath(".a").suffix, nil)
        XCTAssertEqual(RelativePath("a.foo").suffix, "foo")
        XCTAssertEqual(RelativePath(".a.foo").suffix, "foo")
        XCTAssertEqual(RelativePath(".a.foo.bar").suffix, "bar")
        XCTAssertEqual(RelativePath("a.foo.bar").suffix, "bar")
        XCTAssertEqual(RelativePath(".a.foo.bar.baz").suffix, "baz")
    }
    
    func testParentDirectory() {
        XCTAssertEqual(AbsolutePath("/").parentDirectory, AbsolutePath("/"))
        XCTAssertEqual(AbsolutePath("/").parentDirectory.parentDirectory, AbsolutePath("/"))
        XCTAssertEqual(AbsolutePath("/bar").parentDirectory, AbsolutePath("/"))
        XCTAssertEqual(AbsolutePath("/bar/../foo/..//").parentDirectory.parentDirectory, AbsolutePath("/"))
        XCTAssertEqual(AbsolutePath("/bar/../foo/..//yabba/a/b").parentDirectory.parentDirectory, AbsolutePath("/yabba"))
    }
    
    func testHomeDirectory() {
        // Only run tests using HOME if it is defined.
        // FIXME: This needs a lot more testing, especially that the environment variable HOME correctly overrides getpwuid()'s directory etc.
        if POSIX.getenv("HOME") != nil {
            XCTAssertEqual(AbsolutePath("~").asString, POSIX.getenv("HOME"))
        }
    }
    
    // FIXME: We also need tests for join() operations.
    
    // FIXME: We also need tests for dirname, basename, suffix, etc.
    
    // FIXME: We also need test for stat() operations.
    
    // FIXME: We also need performance tests for all of this.
    
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
        ("testHomeDirectory",            testHomeDirectory),
    ]
}
