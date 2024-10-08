/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Foundation
import Testing

#if os(Windows)
private var windows: Bool { true }
#else
private var windows: Bool { false }
#endif

struct PathTests {
    struct AbsolutePathTests {
        @Test(
            arguments: [
                // // basics
                (path: "/", expected: (windows ? #"\"# : "/")),
                (path: "/a", expected: (windows ? #"\a"# : "/a")),
                (path: "/a/b/c", expected: (windows ? #"\a\b\c"# : "/a/b/c")),
                // string literal initialization
                (path: "/", expected: (windows ? #"\"# : "/")),
                // repeated path seperators
                (path: "/ab//cd//ef", expected: (windows ? #"\ab\cd\ef"# : "/ab/cd/ef")),
                (path: "/ab///cd//ef", expected: (windows ? #"\ab\cd\ef"# : "/ab/cd/ef")),
                // trailing path seperators
                (path: "/ab/cd/ef/", expected: (windows ? #"\ab\cd\ef"# : "/ab/cd/ef")),
                (path: "/ab/cd/ef//", expected: (windows ? #"\ab\cd\ef"# : "/ab/cd/ef")),
                // dot path components
                (path: "/ab/././cd//ef", expected: "/ab/cd/ef"),
                (path: "/ab/./cd//ef/.", expected: "/ab/cd/ef"),
                // dot dot path components
                (path: "/..", expected: (windows ? #"\"# : "/")),
                (path: "/../../../../..", expected: (windows ? #"\"# : "/")),
                (path: "/abc/..", expected: (windows ? #"\"# : "/")),
                (path: "/abc/../..", expected: (windows ? #"\"# : "/")),
                (path: "/../abc", expected: (windows ? #"\abc"# : "/abc")),
                (path: "/../abc/..", expected: (windows ? #"\"# : "/")),
                (path: "/../abc/../def", expected: (windows ? #"\def"# : "/def")),
                // combinations and edge cases
                (path: "///", expected: (windows ? #"\"# : "/")),
                (path: "/./", expected: (windows ? #"\"# : "/"))
            ]
        )
        func pathStringIsSetCorrectly(path: String, expected: String) {
            let actual = AbsolutePath(path).pathString

            #expect(actual == expected, "Actual is not as expected")
        }

        @Test(
            arguments: [
                (path: "/", expected: (windows ? #"\"# : "/")),
                (path: "/a", expected: (windows ? #"\"# : "/")),
                (path: "/./a", expected: (windows ? #"\"# : "/")),
                (path: "/../..", expected: (windows ? #"\"# : "/")),
                (path: "/ab/c//d/", expected: (windows ? #"\ab\c"# : "/ab/c"))

            ]
        )
        func dirnameAttributeReturnsExpectedValue(path: String, expected: String) {
            let actual = AbsolutePath(path).dirname

            #expect(actual == expected, "Actual is not as expected")
        }

        @Test(
            arguments: [
                (path: "/", expected: (windows ? #"\"# : "/")),
                (path: "/a", expected: "a"),
                (path: "/./a", expected: "a"),
                (path: "/../..", expected: "/")
            ]
        )
        func basenameAttributeReturnsExpectedValue(path: String, expected: String) {
            let actual = AbsolutePath(path).basename

            #expect(actual == expected, "Actual is not as expected")
        }

        @Test(
            arguments: [
                // path without extension
                (path: "/", expected: (windows ? #"\"# : "/")),
                (path: "/a", expected: "a"),
                (path: "/./a", expected: "a"),
                (path: "/../..", expected: "/"),
                // path with extension
                (path: "/a.txt", expected: "a"),
                (path: "/./a.txt", expected: "a")

            ]
        )
        func basenameWithoutExtAttributeReturnsExpectedValue(path: String, expected: String) {
            let actual = AbsolutePath(path).basenameWithoutExt

            #expect(actual == expected, "Actual is not as expected")
        }

        @Test(
            arguments: [
                (path: "/", numParentDirectoryCalls: 1, expected: "/"),
                (path: "/", numParentDirectoryCalls: 2, expected: "/"),
                (path: "/bar", numParentDirectoryCalls: 1, expected: "/"),
                (path: "/bar/../foo/..//", numParentDirectoryCalls: 2, expected: "/"),
                (path: "/bar/../foo/..//yabba/a/b", numParentDirectoryCalls: 2, expected: "/yabba")
            ]
        )
        func parentDirectoryAttributeReturnsAsExpected(path: String, numParentDirectoryCalls: Int, expected: String) {
            let pathUnderTest = AbsolutePath(path)
            let expectedPath = AbsolutePath(expected)

            var actual = pathUnderTest
            for _ in 0 ..< numParentDirectoryCalls {
                actual = actual.parentDirectory
            }
            #expect(actual == expectedPath)
        }
        @Test(
            arguments: [
                (path:"/", expected: ["/"]),
                (path:"/.", expected: ["/"]),
                (path:"/..", expected: ["/"]),
                (path:"/bar", expected: ["/", "bar"]),
                (path:"/foo/bar/..", expected: ["/", "foo"]),
                (path:"/bar/../foo", expected: ["/", "foo"]),
                (path:"/bar/../foo/..//", expected: ["/"]),
                (path:"/bar/../foo/..//yabba/a/b/", expected: ["/", "yabba", "a", "b"])
            ]
        )
        func componentsAttributeReturnsExpectedValue(path: String, expected: [String]) {
            let actual = AbsolutePath(path).components

            #expect(actual == expected)
        }

        @Test(
            arguments: [
                (path: "/", relativeTo: "/", expected: "."),
                (path: "/a/b/c/d", relativeTo: "/", expected: "a/b/c/d"),
                (path: "/", relativeTo: "/a/b/c", expected: "../../.."),
                (path: "/a/b/c/d", relativeTo: "/a/b", expected: "c/d"),
                (path: "/a/b/c/d", relativeTo: "/a/b/c", expected: "d"),
                (path: "/a/b/c/d", relativeTo: "/a/c/d", expected: "../../b/c/d"),
                (path: "/a/b/c/d", relativeTo: "/b/c/d", expected: "../../../a/b/c/d")
            ]
        )
        func relativePathFromAbsolutePaths(path: String, relativeTo: String, expected: String) {
            let actual = AbsolutePath(path).relative(to: AbsolutePath(relativeTo))
            let expected = RelativePath(expected)

            #expect(actual == expected, "Actual is not as expected")
        }

        @Test
        func comparison() {
            #expect(AbsolutePath("/") <= AbsolutePath("/"));
            #expect(AbsolutePath("/abc") < AbsolutePath("/def"));
            #expect(AbsolutePath("/2") <= AbsolutePath("/2.1"));
            #expect(AbsolutePath("/3.1") > AbsolutePath("/2"));
            #expect(AbsolutePath("/2") >= AbsolutePath("/2"));
            #expect(AbsolutePath("/2.1") >= AbsolutePath("/2"));
        }

        struct ancestryTest{
            @Test(
                arguments: [
                    (path: "/a/b/c/d/e/f", descendentOfOrEqualTo: "/a/b/c/d", expected: true),
                    (path: "/a/b/c/d/e/f.swift", descendentOfOrEqualTo: "/a/b/c", expected: true),
                    (path: "/", descendentOfOrEqualTo: "/", expected: true),
                    (path: "/foo/bar", descendentOfOrEqualTo: "/", expected: true),
                    (path: "/foo/bar", descendentOfOrEqualTo: "/foo/bar/baz", expected: false),
                    (path: "/foo/bar", descendentOfOrEqualTo: "/bar", expected: false)
                    // (path: "", descendentOfOrEqualTo: "", expected: true),
                ]
            )
            func isDescendantOfOrEqual(path: String, descendentOfOrEqualTo: String, expected: Bool) {
                let actual = AbsolutePath(path).isDescendantOfOrEqual(to: AbsolutePath(descendentOfOrEqualTo))

                #expect(actual == expected, "Actual is not as expected")
            }

            @Test(
                arguments: [
                    (path: "/foo/bar", descendentOf: "/foo/bar", expected: false),
                    (path: "/foo/bar", descendentOf: "/foo", expected: true)
                ]
            )
            func isDescendant(path: String, ancesterOf: String, expected: Bool) {
                let actual = AbsolutePath(path).isDescendant(of: AbsolutePath(ancesterOf))

                #expect(actual == expected, "Actual is not as expected")
            }

            @Test(
                arguments: [
                    (path: "/a/b/c/d", ancestorOfOrEqualTo: "/a/b/c/d/e/f", expected: true),
                    (path: "/a/b/c", ancestorOfOrEqualTo: "/a/b/c/d/e/f.swift", expected: true),
                    (path: "/", ancestorOfOrEqualTo: "/", expected: true),
                    (path: "/", ancestorOfOrEqualTo: "/foo/bar", expected: true),
                    (path: "/foo/bar/baz", ancestorOfOrEqualTo: "/foo/bar", expected: false),
                    (path: "/bar", ancestorOfOrEqualTo: "/foo/bar", expected: false),
                ]
            )
            func isAncestorOfOrEqual(path: String, ancestorOfOrEqualTo: String, expected: Bool) {
                let actual = AbsolutePath(path).isAncestorOfOrEqual(to: AbsolutePath(ancestorOfOrEqualTo))

                #expect(actual == expected, "Actual is not as expected")
            }

            @Test(
                arguments: [
                    (path: "/foo/bar", ancesterOf: "/foo/bar", expected: false),
                    (path: "/foo", ancesterOf: "/foo/bar", expected: true),
                ]
            )
            func isAncestor(path: String, ancesterOf: String, expected: Bool) {
                let actual = AbsolutePath(path).isAncestor(of: AbsolutePath(ancesterOf))

                #expect(actual == expected, "Actual is not as expected")
            }
        }

        @Test
        func absolutePathValidation() {
            #expect(throws: Never.self) {
                try AbsolutePath(validating: "/a/b/c/d")
            }

            #expect {try AbsolutePath(validating: "~/a/b/d")} throws: { error in
                ("\(error)" == "invalid absolute path '~/a/b/d'; absolute path must begin with '/'")
            }

            #expect {try AbsolutePath(validating: "a/b/d") } throws: { error in
                ("\(error)" == "invalid absolute path 'a/b/d'")
            }
        }

    }

    struct RelativePathTests {
        @Test(
            arguments: [
                // basics
                (path: ".", expected: "."),
                (path: "a", expected: "a"),
                (path: "a/b/c", expected: (windows ? #"a\b\c"# : "a/b/c")),
                (path: "~", expected: "~"),  // `~` is not special
                // string literal initialization
                (path: ".", expected: "."),
                (path: "~", expected: "~"),  // `~` is not special
                // repeated path seperators
                (path: "ab//cd//ef", expected: (windows ? #"ab\cd\ef"# : "ab/cd/ef")),
                (path: "ab///cd//ef", expected: (windows ? #"ab\cd\ef"# : "ab/cd/ef")),
                // trailing path seperators
                (path: "ab/cd/ef/", expected: (windows ? #"ab\cd\ef"# : "ab/cd/ef")),
                (path: "ab/cd/ef//", expected: (windows ? #"ab\cd\ef"# : "ab/cd/ef")),
                // dot path components
                (path: "ab/./cd/././ef", expected: "ab/cd/ef"),
                (path: "ab/./cd/ef/.", expected: "ab/cd/ef"),
                // dot dot path components
                (path: "..", expected: ".."),
                (path: "../..", expected: "../.."),
                (path: ".././..", expected: "../.."),
                (path: "../abc/..", expected: ".."),
                (path: "../abc/.././", expected: ".."),
                (path: "abc/..", expected: "."),
                // combinations and edge cases
                (path: "", expected: "."),
                (path: ".", expected: "."),
                (path: "./abc", expected: "abc"),
                (path: "./abc/", expected: "abc"),
                (path: "./abc/../bar", expected: "bar"),
                (path: "foo/../bar", expected: "bar"),
                (path: "foo///..///bar///baz", expected: "bar/baz"),
                (path: "foo/../bar/./", expected: "bar"),
                (path: "../abc/def/", expected: "../abc/def"),
                (path: "././././.", expected: "."),
                (path: "./././../.", expected: ".."),
                (path: "./", expected: "."),
                (path: ".//", expected: "."),
                (path: "./.", expected: "."),
                (path: "././", expected: "."),
                (path: "../", expected: ".."),
                (path: "../.", expected: ".."),
                (path: "./..", expected: ".."),
                (path: "./../.", expected: ".."),
                (path: "./////../////./////", expected: ".."),
                (path: "../a", expected: (windows ? #"..\a"# : "../a")),
                (path: "../a/..", expected: ".."),
                (path: "a/..", expected: "."),
                (path: "a/../////../////./////", expected: "..")

            ]
        )
        func pathStringIsSetCorrectly(path: String, expected: String) {
            let actual = RelativePath(path).pathString

            #expect(actual == expected, "Actual is not as expected")
        }

        @Test(
            arguments: [
                (path: "ab/c//d/", expected: (windows ? #"ab\c"# : "ab/c")),
                (path: "../a", expected: ".."),
                (path: "../a/..", expected: "."),
                (path: "a/..", expected: "."),
                (path: "./..", expected: "."),
                (path: "a/../////../////./////", expected: "."),
                (path: "abc", expected: "."),
                (path: "", expected: "."),
                (path: ".", expected: ".")
            ]
        )
        func dirnameAttributeReturnsExpectedValue(path: String, expected: String) {
            let actual = RelativePath(path).dirname

            #expect(actual == expected, "Actual is not as expected")
        }

        @Test(
            arguments: [
                (path: "../..", expected:".."),
                (path: "../a", expected:"a"),
                (path: "../a/..", expected:".."),
                (path: "a/..", expected:"."),
                (path: "./..", expected:".."),
                (path: "a/../////../////./////", expected:".."),
                (path: "abc", expected:"abc"),
                (path: "", expected:"."),
                (path: ".", expected:".")
            ]
        )
        func basenameAttributeReturnsExpectedValue(path: String, expected: String) {
            let actual = RelativePath(path).basename

            #expect(actual == expected, "Actual is not as expected")
        }

        @Test(
            arguments: [
                // path without extension
                (path: "../..", expected: ".."),
                (path: "../a", expected: "a"),
                (path: "../a/..", expected: ".."),
                (path: "a/..", expected: "."),
                (path: "./..", expected: ".."),
                (path: "a/../////../////./////", expected: ".."),
                (path: "abc", expected: "abc"),
                (path: "", expected: "."),
                (path: ".", expected: "."),
                // path with extension
                (path: "../a.bc", expected: "a"),
                (path: "abc.swift", expected: "abc"),
                (path: "../a.b.c", expected: "a.b"),
                (path: "abc.xyz.123", expected: "abc.xyz")
            ]
        )
        func basenameWithoutExtAttributeReturnsExpectedValue(path: String, expected: String) {
            let actual = RelativePath(path).basenameWithoutExt

            #expect(actual == expected, "Actual is not as expected")
        }

        @Test(
            arguments:[
                (path: "a", expectedSuffix: nil, expectedExtension: nil),
                (path: "a.", expectedSuffix: nil, expectedExtension: nil),
                (path: ".a", expectedSuffix: nil, expectedExtension: nil),
                (path: "", expectedSuffix: nil, expectedExtension: nil),
                (path: ".", expectedSuffix: nil, expectedExtension: nil),
                (path: "..", expectedSuffix: nil, expectedExtension: nil),
                (path: "a.foo", expectedSuffix: ".foo", expectedExtension: "foo"),
                (path: ".a.foo", expectedSuffix: ".foo", expectedExtension: "foo"),
                (path: "a.foo.bar", expectedSuffix: ".bar", expectedExtension: "bar"),
                (path: ".a.foo.bar", expectedSuffix: ".bar", expectedExtension: "bar"),
                (path: ".a.foo.bar.baz", expectedSuffix: ".baz", expectedExtension: "baz"),
            ]
        )
        func suffixAndExensionReturnExpectedValue(path: String, expectedSuffix: String?, expectedExtension: String?) {
            let actual = RelativePath(path)

            #expect(actual.suffix == expectedSuffix, "Actual suffix not as expected")
            #expect(actual.extension == expectedExtension, "Actual extension not as expected")
        }

        @Test(
            arguments: [
                (path:"", expected: ["."]),
                (path:".", expected: ["."]),
                (path:"..", expected: [".."]),
                (path:"bar", expected: ["bar"]),
                (path:"foo/bar/..", expected: ["foo"]),
                (path:"bar/../foo", expected: ["foo"]),
                (path:"bar/../foo/..//", expected: ["."]),
                (path:"bar/../foo/..//yabba/a/b/", expected: ["yabba", "a", "b"]),
                (path:"../..", expected: ["..", ".."]),
                (path:".././/..", expected: ["..", ".."]),
                (path:"../a", expected: ["..", "a"]),
                (path:"../a/..", expected: [".."]),
                (path:"a/..", expected: ["."]),
                (path:"./..", expected: [".."]),
                (path:"a/../////../////./////", expected: [".."]),
                (path:"abc", expected: ["abc"])
            ]
        )
        func componentsAttributeReturnsExpectedValue(path: String, expected: [String]) {
            let actual = RelativePath(path).components

            #expect(actual == expected)
        }

        @Test
        func relativePathValidation() {
            #expect(throws: Never.self) {
                try RelativePath(validating: "a/b/c/d")
            }

            #expect {try RelativePath(validating: "/a/b/d")} throws: { error in
                ("\(error)" == "invalid relative path '/a/b/d'; relative path should not begin with '/'")
            }

        }
    }


    @Test
    func stringInitialization() throws {
        let abs1 = AbsolutePath("/")
        let abs2 = AbsolutePath(abs1, ".")
        #expect(abs1 == abs2)
        let rel3 = "."
        let abs3 = try AbsolutePath(abs2, validating: rel3)
        #expect(abs2 == abs3)
        let base = AbsolutePath("/base/path")
        let abs4 = AbsolutePath("/a/b/c", relativeTo: base)
        #expect(abs4 == AbsolutePath("/a/b/c"))
        let abs5 = AbsolutePath("./a/b/c", relativeTo: base)
        #expect(abs5 == AbsolutePath("/base/path/a/b/c"))
        let abs6 = AbsolutePath("~/bla", relativeTo: base)  // `~` isn't special
        #expect(abs6 == AbsolutePath("/base/path/~/bla"))
    }


    @Test
    @available(*, deprecated)
    func concatenation() {
        #expect(AbsolutePath(AbsolutePath("/"), RelativePath("")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath(AbsolutePath("/"), RelativePath(".")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath(AbsolutePath("/"), RelativePath("..")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath(AbsolutePath("/"), RelativePath("bar")).pathString == (windows ? #"\bar"# : "/bar"))
        #expect(AbsolutePath(AbsolutePath("/foo/bar"), RelativePath("..")).pathString == (windows ? #"\foo"# : "/foo"))
        #expect(AbsolutePath(AbsolutePath("/bar"), RelativePath("../foo")).pathString == (windows ? #"\foo"# : "/foo"))
        #expect(AbsolutePath(AbsolutePath("/bar"), RelativePath("../foo/..//")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath(AbsolutePath("/bar/../foo/..//yabba/"), RelativePath("a/b")).pathString == (windows ? #"\yabba\a\b"# : "/yabba/a/b"))

        #expect(AbsolutePath("/").appending(RelativePath("")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath("/").appending(RelativePath(".")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath("/").appending(RelativePath("..")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath("/").appending(RelativePath("bar")).pathString == (windows ? #"\bar"# : "/bar"))
        #expect(AbsolutePath("/foo/bar").appending(RelativePath("..")).pathString == (windows ? #"\foo"# : "/foo"))
        #expect(AbsolutePath("/bar").appending(RelativePath("../foo")).pathString == (windows ? #"\foo"# : "/foo"))
        #expect(AbsolutePath("/bar").appending(RelativePath("../foo/..//")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath("/bar/../foo/..//yabba/").appending(RelativePath("a/b")).pathString == (windows ? #"\yabba\a\b"# : "/yabba/a/b"))

        #expect(AbsolutePath("/").appending(component: "a").pathString == (windows ? #"\a"# : "/a"))
        #expect(AbsolutePath("/a").appending(component: "b").pathString == (windows ? #"\a\b"# : "/a/b"))
        #expect(AbsolutePath("/").appending(components: "a", "b").pathString == (windows ? #"\a\b"# : "/a/b"))
        #expect(AbsolutePath("/a").appending(components: "b", "c").pathString == (windows ? #"\a\b\c"# : "/a/b/c"))

        #expect(AbsolutePath("/a/b/c").appending(components: "", "c").pathString == (windows ? #"\a\b\c\c"# : "/a/b/c/c"))
        #expect(AbsolutePath("/a/b/c").appending(components: "").pathString == (windows ? #"\a\b\c"# : "/a/b/c"))
        #expect(AbsolutePath("/a/b/c").appending(components: ".").pathString == (windows ? #"\a\b\c"# : "/a/b/c"))
        #expect(AbsolutePath("/a/b/c").appending(components: "..").pathString == (windows ? #"\a\b"# : "/a/b"))
        #expect(AbsolutePath("/a/b/c").appending(components: "..", "d").pathString == (windows ? #"\a\b\d"# : "/a/b/d"))
        #expect(AbsolutePath("/").appending(components: "..").pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath("/").appending(components: ".").pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath("/").appending(components: "..", "a").pathString == (windows ? #"\a"# : "/a"))

        #expect(RelativePath("hello").appending(components: "a", "b", "c", "..").pathString == (windows ? #"hello\a\b"# : "hello/a/b"))
        #expect(RelativePath("hello").appending(RelativePath("a/b/../c/d")).pathString == (windows ? #"hello\a\c\d"# : "hello/a/c/d"))
    }

    @Test
    func codable() throws {
        struct AbsolutePathCodable: Codable, Equatable {
            var path: AbsolutePath
        }

        struct RelativePathCodable: Codable, Equatable {
            var path: RelativePath
        }

        struct StringCodable: Codable, Equatable {
            var path: String
        }

        do {
            let foo = AbsolutePathCodable(path: "/path/to/foo")
            let data = try JSONEncoder().encode(foo)
            let decodedFoo = try JSONDecoder().decode(AbsolutePathCodable.self, from: data)
            #expect(foo == decodedFoo)
        }

        do {
            let foo = AbsolutePathCodable(path: "/path/to/../to/foo")
            let data = try JSONEncoder().encode(foo)
            let decodedFoo = try JSONDecoder().decode(AbsolutePathCodable.self, from: data)
            #expect(foo == decodedFoo)
            #expect(foo.path.pathString == (windows ? #"\path\to\foo"# : "/path/to/foo"))
            #expect(decodedFoo.path.pathString == (windows ? #"\path\to\foo"# : "/path/to/foo"))
        }

        do {
            let bar = RelativePathCodable(path: "path/to/bar")
            let data = try JSONEncoder().encode(bar)
            let decodedBar = try JSONDecoder().decode(RelativePathCodable.self, from: data)
            #expect(bar == decodedBar)
        }

        do {
            let bar = RelativePathCodable(path: "path/to/../to/bar")
            let data = try JSONEncoder().encode(bar)
            let decodedBar = try JSONDecoder().decode(RelativePathCodable.self, from: data)
            #expect(bar == decodedBar)
            #expect(bar.path.pathString == "path/to/bar")
            #expect(decodedBar.path.pathString == "path/to/bar")
        }

        do {
            let data = try JSONEncoder().encode(StringCodable(path: ""))
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(AbsolutePathCodable.self, from: data)
            }
            #expect(throws: Never.self) {
                try JSONDecoder().decode(RelativePathCodable.self, from: data)
            } // empty string is a valid relative path
        }

        do {
            let data = try JSONEncoder().encode(StringCodable(path: "foo"))
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(AbsolutePathCodable.self, from: data)
            }
        }

        do {
            let data = try JSONEncoder().encode(StringCodable(path: "/foo"))
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(RelativePathCodable.self, from: data)
            }
        }
    }

    // FIXME: We also need tests for join() operations.

    // FIXME: We also need tests for dirname, basename, suffix, etc.

    // FIXME: We also need test for stat() operations.
}
