/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import Foundation
import XCTest

import _InternalTestSupport // for skipOnWindowsAsTestCurrentlyFails()

#if os(Windows)
private var windows: Bool { true }
#else
private var windows: Bool { false }
#endif

class PathTests: XCTestCase {
    func testBasics() {
        XCTAssertEqual(AbsolutePath("/").pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/a").pathString, windows ? #"\a"# : "/a")
        XCTAssertEqual(AbsolutePath("/a/b/c").pathString, windows ? #"\a\b\c"# : "/a/b/c")
        XCTAssertEqual(RelativePath(".").pathString, ".")
        XCTAssertEqual(RelativePath("a").pathString, "a")
        XCTAssertEqual(RelativePath("a/b/c").pathString, windows ? #"a\b\c"# : "a/b/c")
        XCTAssertEqual(RelativePath("~").pathString, "~")  // `~` is not special
    }

    func testStringInitialization() throws {
        let abs1 = AbsolutePath("/")
        let abs2 = AbsolutePath(abs1, ".")
        XCTAssertEqual(abs1, abs2)
        let rel3 = "."
        let abs3 = try AbsolutePath(abs2, validating: rel3)
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
        XCTAssertEqual(abs.pathString, windows ? #"\"# : "/")
        let rel1 = RelativePath(".")
        XCTAssertEqual(rel1.pathString, ".")
        let rel2 = RelativePath("~")
        XCTAssertEqual(rel2.pathString, "~")  // `~` is not special
    }

    func testRepeatedPathSeparators() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: "all assertions fail")

        XCTAssertEqual(AbsolutePath("/ab//cd//ef").pathString, windows ? #"\ab\cd\ef"# : "/ab/cd/ef")
        XCTAssertEqual(AbsolutePath("/ab///cd//ef").pathString, windows ? #"\ab\cd\ef"# : "/ab/cd/ef")
        XCTAssertEqual(RelativePath("ab//cd//ef").pathString, windows ? #"ab\cd\ef"# : "ab/cd/ef")
        XCTAssertEqual(RelativePath("ab//cd///ef").pathString, windows ? #"ab\cd\ef"# : "ab/cd/ef")
    }

    func testTrailingPathSeparators() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: "trailing path seperator is not removed from pathString")

        XCTAssertEqual(AbsolutePath("/ab/cd/ef/").pathString, windows ? #"\ab\cd\ef"# : "/ab/cd/ef")
        XCTAssertEqual(AbsolutePath("/ab/cd/ef//").pathString, windows ? #"\ab\cd\ef"# : "/ab/cd/ef")
        XCTAssertEqual(RelativePath("ab/cd/ef/").pathString, windows ? #"ab\cd\ef"# : "ab/cd/ef")
        XCTAssertEqual(RelativePath("ab/cd/ef//").pathString, windows ? #"ab\cd\ef"# : "ab/cd/ef")
    }

    func testDotPathComponents() throws {
        try skipOnWindowsAsTestCurrentlyFails()

        XCTAssertEqual(AbsolutePath("/ab/././cd//ef").pathString, "/ab/cd/ef")
        XCTAssertEqual(AbsolutePath("/ab/./cd//ef/.").pathString, "/ab/cd/ef")
        XCTAssertEqual(RelativePath("ab/./cd/././ef").pathString, "ab/cd/ef")
        XCTAssertEqual(RelativePath("ab/./cd/ef/.").pathString, "ab/cd/ef")
    }

    func testDotDotPathComponents() throws {
        try skipOnWindowsAsTestCurrentlyFails()

        XCTAssertEqual(AbsolutePath("/..").pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/../../../../..").pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/abc/..").pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/abc/../..").pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/../abc").pathString, windows ? #"\abc"# : "/abc")
        XCTAssertEqual(AbsolutePath("/../abc/..").pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/../abc/../def").pathString, windows ? #"\def"# : "/def")
        XCTAssertEqual(RelativePath("..").pathString, "..")
        XCTAssertEqual(RelativePath("../..").pathString, "../..")
        XCTAssertEqual(RelativePath(".././..").pathString, "../..")
        XCTAssertEqual(RelativePath("../abc/..").pathString, "..")
        XCTAssertEqual(RelativePath("../abc/.././").pathString, "..")
        XCTAssertEqual(RelativePath("abc/..").pathString, ".")
    }

    func testCombinationsAndEdgeCases() throws {
        try skipOnWindowsAsTestCurrentlyFails()

        XCTAssertEqual(AbsolutePath("///").pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/./").pathString, windows ? #"\"# : "/")
        XCTAssertEqual(RelativePath("").pathString, ".")
        XCTAssertEqual(RelativePath(".").pathString, ".")
        XCTAssertEqual(RelativePath("./abc").pathString, "abc")
        XCTAssertEqual(RelativePath("./abc/").pathString, "abc")
        XCTAssertEqual(RelativePath("./abc/../bar").pathString, "bar")
        XCTAssertEqual(RelativePath("foo/../bar").pathString, "bar")
        XCTAssertEqual(RelativePath("foo///..///bar///baz").pathString, "bar/baz")
        XCTAssertEqual(RelativePath("foo/../bar/./").pathString, "bar")
        XCTAssertEqual(RelativePath("../abc/def/").pathString, "../abc/def")
        XCTAssertEqual(RelativePath("././././.").pathString, ".")
        XCTAssertEqual(RelativePath("./././../.").pathString, "..")
        XCTAssertEqual(RelativePath("./").pathString, ".")
        XCTAssertEqual(RelativePath(".//").pathString, ".")
        XCTAssertEqual(RelativePath("./.").pathString, ".")
        XCTAssertEqual(RelativePath("././").pathString, ".")
        XCTAssertEqual(RelativePath("../").pathString, "..")
        XCTAssertEqual(RelativePath("../.").pathString, "..")
        XCTAssertEqual(RelativePath("./..").pathString, "..")
        XCTAssertEqual(RelativePath("./../.").pathString, "..")
        XCTAssertEqual(RelativePath("./////../////./////").pathString, "..")
        XCTAssertEqual(RelativePath("../a").pathString, windows ? #"..\a"# : "../a")
        XCTAssertEqual(RelativePath("../a/..").pathString, "..")
        XCTAssertEqual(RelativePath("a/..").pathString, ".")
        XCTAssertEqual(RelativePath("a/../////../////./////").pathString, "..")
    }

    func testDirectoryNameExtraction() throws {
        try skipOnWindowsAsTestCurrentlyFails()

        XCTAssertEqual(AbsolutePath("/").dirname, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/a").dirname, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/./a").dirname, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/../..").dirname, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/ab/c//d/").dirname, windows ? #"\ab\c"# : "/ab/c")
        XCTAssertEqual(RelativePath("ab/c//d/").dirname, windows ? #"ab\c"# : "ab/c")
        XCTAssertEqual(RelativePath("../a").dirname, "..")
        XCTAssertEqual(RelativePath("../a/..").dirname, ".")
        XCTAssertEqual(RelativePath("a/..").dirname, ".")
        XCTAssertEqual(RelativePath("./..").dirname, ".")
        XCTAssertEqual(RelativePath("a/../////../////./////").dirname, ".")
        XCTAssertEqual(RelativePath("abc").dirname, ".")
        XCTAssertEqual(RelativePath("").dirname, ".")
        XCTAssertEqual(RelativePath(".").dirname, ".")
    }

    func testBaseNameExtraction() throws {
        try skipOnWindowsAsTestCurrentlyFails()

        XCTAssertEqual(AbsolutePath("/").basename, windows ? #"\"# : "/")
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

    func testBaseNameWithoutExt() throws{
        try skipOnWindowsAsTestCurrentlyFails()

        XCTAssertEqual(AbsolutePath("/").basenameWithoutExt, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/a").basenameWithoutExt, "a")
        XCTAssertEqual(AbsolutePath("/./a").basenameWithoutExt, "a")
        XCTAssertEqual(AbsolutePath("/../..").basenameWithoutExt, "/")
        XCTAssertEqual(RelativePath("../..").basenameWithoutExt, "..")
        XCTAssertEqual(RelativePath("../a").basenameWithoutExt, "a")
        XCTAssertEqual(RelativePath("../a/..").basenameWithoutExt, "..")
        XCTAssertEqual(RelativePath("a/..").basenameWithoutExt, ".")
        XCTAssertEqual(RelativePath("./..").basenameWithoutExt, "..")
        XCTAssertEqual(RelativePath("a/../////../////./////").basenameWithoutExt, "..")
        XCTAssertEqual(RelativePath("abc").basenameWithoutExt, "abc")
        XCTAssertEqual(RelativePath("").basenameWithoutExt, ".")
        XCTAssertEqual(RelativePath(".").basenameWithoutExt, ".")

        XCTAssertEqual(AbsolutePath("/a.txt").basenameWithoutExt, "a")
        XCTAssertEqual(AbsolutePath("/./a.txt").basenameWithoutExt, "a")
        XCTAssertEqual(RelativePath("../a.bc").basenameWithoutExt, "a")
        XCTAssertEqual(RelativePath("abc.swift").basenameWithoutExt, "abc")
        XCTAssertEqual(RelativePath("../a.b.c").basenameWithoutExt, "a.b")
        XCTAssertEqual(RelativePath("abc.xyz.123").basenameWithoutExt, "abc.xyz")
    }

    func testSuffixExtraction() throws {
        try skipOnWindowsAsTestCurrentlyFails(because: "expected nil is not the actual")

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

    func testParentDirectory() throws {
        try skipOnWindowsAsTestCurrentlyFails()

        XCTAssertEqual(AbsolutePath("/").parentDirectory, AbsolutePath("/"))
        XCTAssertEqual(AbsolutePath("/").parentDirectory.parentDirectory, AbsolutePath("/"))
        XCTAssertEqual(AbsolutePath("/bar").parentDirectory, AbsolutePath("/"))
        XCTAssertEqual(AbsolutePath("/bar/../foo/..//").parentDirectory.parentDirectory, AbsolutePath("/"))
        XCTAssertEqual(AbsolutePath("/bar/../foo/..//yabba/a/b").parentDirectory.parentDirectory, AbsolutePath("/yabba"))
    }

    @available(*, deprecated)
    func testConcatenation() throws {
        try skipOnWindowsAsTestCurrentlyFails()

        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), RelativePath("")).pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), RelativePath(".")).pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), RelativePath("..")).pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/"), RelativePath("bar")).pathString, windows ? #"\bar"# : "/bar")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/foo/bar"), RelativePath("..")).pathString, windows ? #"\foo"# : "/foo")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/bar"), RelativePath("../foo")).pathString, windows ? #"\foo"# : "/foo")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/bar"), RelativePath("../foo/..//")).pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath(AbsolutePath("/bar/../foo/..//yabba/"), RelativePath("a/b")).pathString, windows ? #"\yabba\a\b"# : "/yabba/a/b")

        XCTAssertEqual(AbsolutePath("/").appending(RelativePath("")).pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/").appending(RelativePath(".")).pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/").appending(RelativePath("..")).pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/").appending(RelativePath("bar")).pathString, windows ? #"\bar"# : "/bar")
        XCTAssertEqual(AbsolutePath("/foo/bar").appending(RelativePath("..")).pathString, windows ? #"\foo"# : "/foo")
        XCTAssertEqual(AbsolutePath("/bar").appending(RelativePath("../foo")).pathString, windows ? #"\foo"# : "/foo")
        XCTAssertEqual(AbsolutePath("/bar").appending(RelativePath("../foo/..//")).pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/bar/../foo/..//yabba/").appending(RelativePath("a/b")).pathString, windows ? #"\yabba\a\b"# : "/yabba/a/b")

        XCTAssertEqual(AbsolutePath("/").appending(component: "a").pathString, windows ? #"\a"# : "/a")
        XCTAssertEqual(AbsolutePath("/a").appending(component: "b").pathString, windows ? #"\a\b"# : "/a/b")
        XCTAssertEqual(AbsolutePath("/").appending(components: "a", "b").pathString, windows ? #"\a\b"# : "/a/b")
        XCTAssertEqual(AbsolutePath("/a").appending(components: "b", "c").pathString, windows ? #"\a\b\c"# : "/a/b/c")

        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: "", "c").pathString, windows ? #"\a\b\c\c"# : "/a/b/c/c")
        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: "").pathString, windows ? #"\a\b\c"# : "/a/b/c")
        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: ".").pathString, windows ? #"\a\b\c"# : "/a/b/c")
        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: "..").pathString, windows ? #"\a\b"# : "/a/b")
        XCTAssertEqual(AbsolutePath("/a/b/c").appending(components: "..", "d").pathString, windows ? #"\a\b\d"# : "/a/b/d")
        XCTAssertEqual(AbsolutePath("/").appending(components: "..").pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/").appending(components: ".").pathString, windows ? #"\"# : "/")
        XCTAssertEqual(AbsolutePath("/").appending(components: "..", "a").pathString, windows ? #"\a"# : "/a")

        XCTAssertEqual(RelativePath("hello").appending(components: "a", "b", "c", "..").pathString, windows ? #"hello\a\b"# : "hello/a/b")
        XCTAssertEqual(RelativePath("hello").appending(RelativePath("a/b/../c/d")).pathString, windows ? #"hello\a\c\d"# : "hello/a/c/d")
    }

    func testPathComponents() throws {
        try skipOnWindowsAsTestCurrentlyFails()

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

    func testRelativePathFromAbsolutePaths() throws {
        try skipOnWindowsAsTestCurrentlyFails()

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

    func testAncestry() {
        XCTAssertTrue(AbsolutePath("/a/b/c/d/e/f").isDescendantOfOrEqual(to: AbsolutePath("/a/b/c/d")))
        XCTAssertTrue(AbsolutePath("/a/b/c/d/e/f.swift").isDescendantOfOrEqual(to: AbsolutePath("/a/b/c")))
        XCTAssertTrue(AbsolutePath("/").isDescendantOfOrEqual(to: AbsolutePath("/")))
        XCTAssertTrue(AbsolutePath("/foo/bar").isDescendantOfOrEqual(to: AbsolutePath("/")))
        XCTAssertFalse(AbsolutePath("/foo/bar").isDescendantOfOrEqual(to: AbsolutePath("/foo/bar/baz")))
        XCTAssertFalse(AbsolutePath("/foo/bar").isDescendantOfOrEqual(to: AbsolutePath("/bar")))

        XCTAssertFalse(AbsolutePath("/foo/bar").isDescendant(of: AbsolutePath("/foo/bar")))
        XCTAssertTrue(AbsolutePath("/foo/bar").isDescendant(of: AbsolutePath("/foo")))

        XCTAssertTrue(AbsolutePath("/a/b/c/d").isAncestorOfOrEqual(to: AbsolutePath("/a/b/c/d/e/f")))
        XCTAssertTrue(AbsolutePath("/a/b/c").isAncestorOfOrEqual(to: AbsolutePath("/a/b/c/d/e/f.swift")))
        XCTAssertTrue(AbsolutePath("/").isAncestorOfOrEqual(to: AbsolutePath("/")))
        XCTAssertTrue(AbsolutePath("/").isAncestorOfOrEqual(to: AbsolutePath("/foo/bar")))
        XCTAssertFalse(AbsolutePath("/foo/bar/baz").isAncestorOfOrEqual(to: AbsolutePath("/foo/bar")))
        XCTAssertFalse(AbsolutePath("/bar").isAncestorOfOrEqual(to: AbsolutePath("/foo/bar")))

        XCTAssertFalse(AbsolutePath("/foo/bar").isAncestor(of: AbsolutePath("/foo/bar")))
        XCTAssertTrue(AbsolutePath("/foo").isAncestor(of: AbsolutePath("/foo/bar")))
    }

    func testAbsolutePathValidation() throws {
        try skipOnWindowsAsTestCurrentlyFails()

        XCTAssertNoThrow(try AbsolutePath(validating: "/a/b/c/d"))

        XCTAssertThrowsError(try AbsolutePath(validating: "~/a/b/d")) { error in
            XCTAssertEqual("\(error)", "invalid absolute path '~/a/b/d'; absolute path must begin with '/'")
        }

        XCTAssertThrowsError(try AbsolutePath(validating: "a/b/d")) { error in
            XCTAssertEqual("\(error)", "invalid absolute path 'a/b/d'")
        }
    }

    func testRelativePathValidation() throws {
        try skipOnWindowsAsTestCurrentlyFails()

        XCTAssertNoThrow(try RelativePath(validating: "a/b/c/d"))

        XCTAssertThrowsError(try RelativePath(validating: "/a/b/d")) { error in
            XCTAssertEqual("\(error)", "invalid relative path '/a/b/d'; relative path should not begin with '/'")
            //XCTAssertEqual("\(error)", "invalid relative path '/a/b/d'; relative path should not begin with '/' or '~'")
        }

        /*XCTAssertThrowsError(try RelativePath(validating: "~/a/b/d")) { error in
            XCTAssertEqual("\(error)", "invalid relative path '~/a/b/d'; relative path should not begin with '/' or '~'")
        }*/
    }

    func testCodable() throws {
        try skipOnWindowsAsTestCurrentlyFails()

        struct Foo: Codable, Equatable {
            var path: AbsolutePath
        }

        struct Bar: Codable, Equatable {
            var path: RelativePath
        }

        struct Baz: Codable, Equatable {
            var path: String
        }

        do {
            let foo = Foo(path: "/path/to/foo")
            let data = try JSONEncoder().encode(foo)
            let decodedFoo = try JSONDecoder().decode(Foo.self, from: data)
            XCTAssertEqual(foo, decodedFoo)
        }

        do {
            let foo = Foo(path: "/path/to/../to/foo")
            let data = try JSONEncoder().encode(foo)
            let decodedFoo = try JSONDecoder().decode(Foo.self, from: data)
            XCTAssertEqual(foo, decodedFoo)
            XCTAssertEqual(foo.path.pathString, windows ? #"\path\to\foo"# : "/path/to/foo")
            XCTAssertEqual(decodedFoo.path.pathString, windows ? #"\path\to\foo"# : "/path/to/foo")
        }

        do {
            let bar = Bar(path: "path/to/bar")
            let data = try JSONEncoder().encode(bar)
            let decodedBar = try JSONDecoder().decode(Bar.self, from: data)
            XCTAssertEqual(bar, decodedBar)
        }

        do {
            let bar = Bar(path: "path/to/../to/bar")
            let data = try JSONEncoder().encode(bar)
            let decodedBar = try JSONDecoder().decode(Bar.self, from: data)
            XCTAssertEqual(bar, decodedBar)
            XCTAssertEqual(bar.path.pathString, "path/to/bar")
            XCTAssertEqual(decodedBar.path.pathString, "path/to/bar")
        }

        do {
            let data = try JSONEncoder().encode(Baz(path: ""))
            XCTAssertThrowsError(try JSONDecoder().decode(Foo.self, from: data))
            XCTAssertNoThrow(try JSONDecoder().decode(Bar.self, from: data)) // empty string is a valid relative path
        }

        do {
            let data = try JSONEncoder().encode(Baz(path: "foo"))
            XCTAssertThrowsError(try JSONDecoder().decode(Foo.self, from: data))
        }

        do {
            let data = try JSONEncoder().encode(Baz(path: "/foo"))
            XCTAssertThrowsError(try JSONDecoder().decode(Bar.self, from: data))
        }
    }

    // FIXME: We also need tests for join() operations.

    // FIXME: We also need tests for dirname, basename, suffix, etc.

    // FIXME: We also need test for stat() operations.
}
