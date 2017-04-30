/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import POSIX

class PathTests: XCTestCase {
    
    func testBasics() {
        XCTAssertEqual(AbsolutePath("/").asString, "/")
        XCTAssertEqual(AbsolutePath("/a").asString, "/a")
        XCTAssertEqual(AbsolutePath("/a/b/c").asString, "/a/b/c")
        XCTAssertEqual(RelativePath(".").asString, ".")
        XCTAssertEqual(RelativePath("a").asString, "a")
        XCTAssertEqual(RelativePath("a/b/c").asString, "a/b/c")
        XCTAssertEqual(RelativePath("~").asString, "~")  // `~` is not special
    }
    
    func testStringInitialization() {
        let abs1 = AbsolutePath("/")
        let abs2 = AbsolutePath(abs1, ".")
        XCTAssertEqual(abs1, abs2)
        let rel3 = "."
        let abs3 = AbsolutePath(abs2, rel3)
        XCTAssertEqual(abs2, abs3)
        let base = AbsolutePath("/base/path")
        let abs4 = AbsolutePath("/a/b/c", relativeTo: base)
        XCTAssertEqual(abs4, AbsolutePath("/a/b/c"))
        let abs5 = AbsolutePath("./a/b/c", relativeTo: base)
        XCTAssertEqual(abs5, AbsolutePath("/base/path/a/b/c"))
        let abs6 = AbsolutePath("~/bla", relativeTo: base)  // `~` isn't special
        XCTAssertEqual(abs6, AbsolutePath("/base/path/~/bla"))
    }
    
    func testStringLiteralInitialization() {
        let abs = AbsolutePath("/")
        XCTAssertEqual(abs.asString, "/")
        let rel1 = RelativePath(".")
        XCTAssertEqual(rel1.asString, ".")
        let rel2 = RelativePath("~")
        XCTAssertEqual(rel2.asString, "~")  // `~` is not special
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
        XCTAssertEqual(RelativePath("a").extension, nil)
        XCTAssertEqual(RelativePath("a.").suffix, nil)
        XCTAssertEqual(RelativePath("a.").extension, nil)
        XCTAssertEqual(RelativePath(".a").suffix, nil)
        XCTAssertEqual(RelativePath(".a").extension, nil)
        XCTAssertEqual(RelativePath("").suffix, nil)
        XCTAssertEqual(RelativePath("").extension, nil)
        XCTAssertEqual(RelativePath(".").suffix, nil)
        XCTAssertEqual(RelativePath(".").extension, nil)
        XCTAssertEqual(RelativePath("..").suffix, nil)
        XCTAssertEqual(RelativePath("..").extension, nil)
        XCTAssertEqual(RelativePath("a.foo").suffix, ".foo")
        XCTAssertEqual(RelativePath("a.foo").extension, "foo")
        XCTAssertEqual(RelativePath(".a.foo").suffix, ".foo")
        XCTAssertEqual(RelativePath(".a.foo").extension, "foo")
        XCTAssertEqual(RelativePath(".a.foo.bar").suffix, ".bar")
        XCTAssertEqual(RelativePath(".a.foo.bar").extension, "bar")
        XCTAssertEqual(RelativePath("a.foo.bar").suffix, ".bar")
        XCTAssertEqual(RelativePath("a.foo.bar").extension, "bar")
        XCTAssertEqual(RelativePath(".a.foo.bar.baz").suffix, ".baz")
        XCTAssertEqual(RelativePath(".a.foo.bar.baz").extension, "baz")
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
        
        XCTAssertEqual(AbsolutePath("/").appending(RelativePath("")).asString, "/")
        XCTAssertEqual(AbsolutePath("/").appending(RelativePath(".")).asString, "/")
        XCTAssertEqual(AbsolutePath("/").appending(RelativePath("..")).asString, "/")
        XCTAssertEqual(AbsolutePath("/").appending(RelativePath("bar")).asString, "/bar")
        XCTAssertEqual(AbsolutePath("/foo/bar").appending(RelativePath("..")).asString, "/foo")
        XCTAssertEqual(AbsolutePath("/bar").appending(RelativePath("../foo")).asString, "/foo")
        XCTAssertEqual(AbsolutePath("/bar").appending(RelativePath("../foo/..//")).asString, "/")
        XCTAssertEqual(AbsolutePath("/bar/../foo/..//yabba/").appending(RelativePath("a/b")).asString, "/yabba/a/b")

        XCTAssertEqual(AbsolutePath("/").appending(component: "a").asString, "/a")
        XCTAssertEqual(AbsolutePath("/a").appending(component: "b").asString, "/a/b")
        XCTAssertEqual(AbsolutePath("/").appending(components: "a", "b").asString, "/a/b")
        XCTAssertEqual(AbsolutePath("/a").appending(components: "b", "c").asString, "/a/b/c")

        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: "", "c").asString, "/a/b/c/c")
        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: "").asString, "/a/b/c")
        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: ".").asString, "/a/b/c")
        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: "..").asString, "/a/b")
        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: "..", "d").asString, "/a/b/d")
        XCTAssertEqual(AbsolutePath("/").appending(components: "..").asString, "/")
        XCTAssertEqual(AbsolutePath("/").appending(components: ".").asString, "/")
        XCTAssertEqual(AbsolutePath("/").appending(components: "..", "a").asString, "/a")
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
    
    func testComparison() {
        XCTAssertTrue(AbsolutePath("/") <= AbsolutePath("/"));
        XCTAssertTrue(AbsolutePath("/abc") < AbsolutePath("/def"));
        XCTAssertTrue(AbsolutePath("/2") <= AbsolutePath("/2.1"));
        XCTAssertTrue(AbsolutePath("/3.1") > AbsolutePath("/2"));
        XCTAssertTrue(AbsolutePath("/2") >= AbsolutePath("/2"));
        XCTAssertTrue(AbsolutePath("/2.1") >= AbsolutePath("/2"));
    }

    func testContains() {
        XCTAssertTrue(AbsolutePath("/a/b/c/d/e/f").contains(AbsolutePath("/a/b/c/d")))
        XCTAssertTrue(AbsolutePath("/a/b/c/d/e/f.swift").contains(AbsolutePath("/a/b/c")))
        XCTAssertTrue(AbsolutePath("/").contains(AbsolutePath("/")))
        XCTAssertTrue(AbsolutePath("/foo/bar").contains(AbsolutePath("/")))
        XCTAssertFalse(AbsolutePath("/foo/bar").contains(AbsolutePath("/foo/bar/baz")))
        XCTAssertFalse(AbsolutePath("/foo/bar").contains(AbsolutePath("/bar")))
    }
    
    // FIXME: We also need tests for join() operations.
    
    // FIXME: We also need tests for dirname, basename, suffix, etc.
    
    // FIXME: We also need test for stat() operations.
        
    static var allTests = [
        ("testBasics",                        testBasics),
        ("testContains",                      testContains),
        ("testStringInitialization",          testStringInitialization),
        ("testStringLiteralInitialization",   testStringLiteralInitialization),
        ("testRepeatedPathSeparators",        testRepeatedPathSeparators),
        ("testTrailingPathSeparators",        testTrailingPathSeparators),
        ("testDotPathComponents",             testDotPathComponents),
        ("testDotDotPathComponents",          testDotDotPathComponents),
        ("testCombinationsAndEdgeCases",      testCombinationsAndEdgeCases),
        ("testDirectoryNameExtraction",       testDirectoryNameExtraction),
        ("testBaseNameExtraction",            testBaseNameExtraction),
        ("testSuffixExtraction",              testSuffixExtraction),
        ("testParentDirectory",               testParentDirectory),
        ("testConcatenation",                 testConcatenation),
        ("testPathComponents",                testPathComponents),
        ("testRelativePathFromAbsolutePaths", testRelativePathFromAbsolutePaths),
        ("testComparison",                    testComparison),
    ]
}
