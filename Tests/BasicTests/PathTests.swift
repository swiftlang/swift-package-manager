/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Foundation

import Basic
import POSIX

class PathTests: XCTestCase {
    
    func testBasics() {
        XCTAssertEqual(AbsolutePath("/").description, "/")
        XCTAssertEqual(AbsolutePath("/a").description, "/a")
        XCTAssertEqual(AbsolutePath("/a/b/c").description, "/a/b/c")
        XCTAssertEqual(RelativePath(".").description, ".")
        XCTAssertEqual(RelativePath("a").description, "a")
        XCTAssertEqual(RelativePath("a/b/c").description, "a/b/c")
        XCTAssertEqual(RelativePath("~").description, "~")  // `~` is not special
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
        XCTAssertEqual(abs.description, "/")
        let rel1 = RelativePath(".")
        XCTAssertEqual(rel1.description, ".")
        let rel2 = RelativePath("~")
        XCTAssertEqual(rel2.description, "~")  // `~` is not special
    }
    
    func testRepeatedPathSeparators() {
        XCTAssertEqual(AbsolutePath("/ab//cd//ef").description, "/ab/cd/ef")
        XCTAssertEqual(AbsolutePath("/ab///cd//ef").description, "/ab/cd/ef")
        XCTAssertEqual(RelativePath("ab//cd//ef").description, "ab/cd/ef")
        XCTAssertEqual(RelativePath("ab//cd///ef").description, "ab/cd/ef")
    }
    
    func testTrailingPathSeparators() {
        XCTAssertEqual(AbsolutePath("/ab/cd/ef/").description, "/ab/cd/ef")
        XCTAssertEqual(AbsolutePath("/ab/cd/ef//").description, "/ab/cd/ef")
        XCTAssertEqual(RelativePath("ab/cd/ef/").description, "ab/cd/ef")
        XCTAssertEqual(RelativePath("ab/cd/ef//").description, "ab/cd/ef")
    }
    
    func testDotPathComponents() {
        XCTAssertEqual(AbsolutePath("/ab/././cd//ef").description, "/ab/cd/ef")
        XCTAssertEqual(AbsolutePath("/ab/./cd//ef/.").description, "/ab/cd/ef")
        XCTAssertEqual(RelativePath("ab/./cd/././ef").description, "ab/cd/ef")
        XCTAssertEqual(RelativePath("ab/./cd/ef/.").description, "ab/cd/ef")
    }
    
    func testDotDotPathComponents() {
        XCTAssertEqual(AbsolutePath("/..").description, "/")
        XCTAssertEqual(AbsolutePath("/../../../../..").description, "/")
        XCTAssertEqual(AbsolutePath("/abc/..").description, "/")
        XCTAssertEqual(AbsolutePath("/abc/../..").description, "/")
        XCTAssertEqual(AbsolutePath("/../abc").description, "/abc")
        XCTAssertEqual(AbsolutePath("/../abc/..").description, "/")
        XCTAssertEqual(AbsolutePath("/../abc/../def").description, "/def")
        XCTAssertEqual(RelativePath("..").description, "..")
        XCTAssertEqual(RelativePath("../..").description, "../..")
        XCTAssertEqual(RelativePath(".././..").description, "../..")
        XCTAssertEqual(RelativePath("../abc/..").description, "..")
        XCTAssertEqual(RelativePath("../abc/.././").description, "..")
        XCTAssertEqual(RelativePath("abc/..").description, ".")
    }
    
    func testCombinationsAndEdgeCases() {
        XCTAssertEqual(AbsolutePath("///").description, "/")
        XCTAssertEqual(AbsolutePath("/./").description, "/")
        XCTAssertEqual(RelativePath("").description, ".")
        XCTAssertEqual(RelativePath(".").description, ".")
        XCTAssertEqual(RelativePath("./abc").description, "abc")
        XCTAssertEqual(RelativePath("./abc/").description, "abc")
        XCTAssertEqual(RelativePath("./abc/../bar").description, "bar")
        XCTAssertEqual(RelativePath("foo/../bar").description, "bar")
        XCTAssertEqual(RelativePath("foo///..///bar///baz").description, "bar/baz")
        XCTAssertEqual(RelativePath("foo/../bar/./").description, "bar")
        XCTAssertEqual(RelativePath("../abc/def/").description, "../abc/def")
        XCTAssertEqual(RelativePath("././././.").description, ".")
        XCTAssertEqual(RelativePath("./././../.").description, "..")
        XCTAssertEqual(RelativePath("./").description, ".")
        XCTAssertEqual(RelativePath(".//").description, ".")
        XCTAssertEqual(RelativePath("./.").description, ".")
        XCTAssertEqual(RelativePath("././").description, ".")
        XCTAssertEqual(RelativePath("../").description, "..")
        XCTAssertEqual(RelativePath("../.").description, "..")
        XCTAssertEqual(RelativePath("./..").description, "..")
        XCTAssertEqual(RelativePath("./../.").description, "..")
        XCTAssertEqual(RelativePath("./////../////./////").description, "..")
        XCTAssertEqual(RelativePath("../a").description, "../a")
        XCTAssertEqual(RelativePath("../a/..").description, "..")
        XCTAssertEqual(RelativePath("a/..").description, ".")
        XCTAssertEqual(RelativePath("a/../////../////./////").description, "..")
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
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), RelativePath("")).description, "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), RelativePath(".")).description, "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), RelativePath("..")).description, "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), RelativePath("bar")).description, "/bar")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/foo/bar"), RelativePath("..")).description, "/foo")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/bar"), RelativePath("../foo")).description, "/foo")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/bar"), RelativePath("../foo/..//")).description, "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/bar/../foo/..//yabba/"), RelativePath("a/b")).description, "/yabba/a/b")
        
        XCTAssertEqual(AbsolutePath("/").appending(RelativePath("")).description, "/")
        XCTAssertEqual(AbsolutePath("/").appending(RelativePath(".")).description, "/")
        XCTAssertEqual(AbsolutePath("/").appending(RelativePath("..")).description, "/")
        XCTAssertEqual(AbsolutePath("/").appending(RelativePath("bar")).description, "/bar")
        XCTAssertEqual(AbsolutePath("/foo/bar").appending(RelativePath("..")).description, "/foo")
        XCTAssertEqual(AbsolutePath("/bar").appending(RelativePath("../foo")).description, "/foo")
        XCTAssertEqual(AbsolutePath("/bar").appending(RelativePath("../foo/..//")).description, "/")
        XCTAssertEqual(AbsolutePath("/bar/../foo/..//yabba/").appending(RelativePath("a/b")).description, "/yabba/a/b")

        XCTAssertEqual(AbsolutePath("/").appending(component: "a").description, "/a")
        XCTAssertEqual(AbsolutePath("/a").appending(component: "b").description, "/a/b")
        XCTAssertEqual(AbsolutePath("/").appending(components: "a", "b").description, "/a/b")
        XCTAssertEqual(AbsolutePath("/a").appending(components: "b", "c").description, "/a/b/c")

        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: "", "c").description, "/a/b/c/c")
        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: "").description, "/a/b/c")
        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: ".").description, "/a/b/c")
        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: "..").description, "/a/b")
        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: "..", "d").description, "/a/b/d")
        XCTAssertEqual(AbsolutePath("/").appending(components: "..").description, "/")
        XCTAssertEqual(AbsolutePath("/").appending(components: ".").description, "/")
        XCTAssertEqual(AbsolutePath("/").appending(components: "..", "a").description, "/a")
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
    
    func testAbsolutePathValidation() {
        XCTAssertNoThrow(try AbsolutePath(validating: "/a/b/c/d"))

        XCTAssertThrowsError(try AbsolutePath(validating: "~/a/b/d")) { error in
            XCTAssertEqual("\(error)", "invalid absolute path '~/a/b/d'; absolute path must begin with '/'")
        }

        XCTAssertThrowsError(try AbsolutePath(validating: "a/b/d")) { error in
            XCTAssertEqual("\(error)", "invalid absolute path 'a/b/d'")
        }
    }

    func testRelativePathValidation() {
        XCTAssertNoThrow(try RelativePath(validating: "a/b/c/d"))

        XCTAssertThrowsError(try RelativePath(validating: "/a/b/d")) { error in
            XCTAssertEqual("\(error)", "invalid relative path '/a/b/d'; relative path should not begin with '/' or '~'")
        }

        XCTAssertThrowsError(try RelativePath(validating: "~/a/b/d")) { error in
            XCTAssertEqual("\(error)", "invalid relative path '~/a/b/d'; relative path should not begin with '/' or '~'")
        }
    }

    func testCodable() throws {
        struct Foo: Codable, Equatable {
            var path: AbsolutePath
        }

        struct Bar: Codable, Equatable {
            var path: RelativePath
        }

        do {
            let foo = Foo(path: AbsolutePath("/path/to/foo"))
            let data = try JSONEncoder().encode(foo)
            let decodedFoo = try JSONDecoder().decode(Foo.self, from: data)
            XCTAssertEqual(foo, decodedFoo)
        }

        do {
            let foo = Foo(path: AbsolutePath("/path/to/../to/foo"))
            let data = try JSONEncoder().encode(foo)
            let decodedFoo = try JSONDecoder().decode(Foo.self, from: data)
            XCTAssertEqual(foo, decodedFoo)
            XCTAssertEqual(foo.path.description, "/path/to/foo")
            XCTAssertEqual(decodedFoo.path.description, "/path/to/foo")
        }

        do {
            let bar = Bar(path: RelativePath("path/to/bar"))
            let data = try JSONEncoder().encode(bar)
            let decodedBar = try JSONDecoder().decode(Bar.self, from: data)
            XCTAssertEqual(bar, decodedBar)
        }

        do {
            let bar = Bar(path: RelativePath("path/to/../to/bar"))
            let data = try JSONEncoder().encode(bar)
            let decodedBar = try JSONDecoder().decode(Bar.self, from: data)
            XCTAssertEqual(bar, decodedBar)
            XCTAssertEqual(bar.path.description, "path/to/bar")
            XCTAssertEqual(decodedBar.path.description, "path/to/bar")
        }
    }

    // FIXME: We also need tests for join() operations.
    
    // FIXME: We also need tests for dirname, basename, suffix, etc.
    
    // FIXME: We also need test for stat() operations.
}
