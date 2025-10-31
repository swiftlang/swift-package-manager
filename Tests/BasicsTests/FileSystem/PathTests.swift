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


@Suite(
    .tags(
        .TestSize.small,
        .Platform.FileSystem,
    ),
)
struct PathTests {
    struct AbsolutePathTests {
        private func pathStringIsSetCorrectlyTestImplementation(path: String, expected: String, label: String) {
            let actual = AbsolutePath(path).pathString

            #expect(actual == expected, "\(label): Actual is not as expected. Path is: \(path)")
        }

        @Test(
            arguments: [
                (path: "/", expected: (windows ? #"\"# : "/"), label: "Basics"),
                (path: "/a", expected: (windows ? #"\a"# : "/a"), label: "Basics"),
                (path: "/a/b/c", expected: (windows ? #"\a\b\c"# : "/a/b/c"), label: "Basics"),
            ]
        )
        func pathStringIsSetCorrectly(path: String, expected: String, label: String) {
            pathStringIsSetCorrectlyTestImplementation(
                path: path,
                expected: expected,
                label: label
            )
        }

        @Test(
            .IssueWindowsPathTestsFailures,
            arguments: [
                (path: "/ab/cd/ef/", expected: (windows ? #"\ab\cd\ef"# : "/ab/cd/ef"), label: "Trailing path seperator"),
                (path: "/ab/cd/ef//", expected: (windows ? #"\ab\cd\ef"# : "/ab/cd/ef"), label: "Trailing path seperator"),
                (path: "/ab/cd/ef///", expected: (windows ? #"\ab\cd\ef"# : "/ab/cd/ef"), label: "Trailing path seperator"),
                (path: "/ab//cd//ef", expected: (windows ? #"\ab\cd\ef"# : "/ab/cd/ef"), label: "repeated path seperators"),
                (path: "/ab///cd//ef", expected: (windows ? #"\ab\cd\ef"# : "/ab/cd/ef"), label: "repeated path seperators"),
                (path: "/ab/././cd//ef", expected: "/ab/cd/ef", label: "dot path component"),
                (path: "/ab/./cd//ef/.", expected:  "/ab/cd/ef", label: "dot path component"),
                (path: "/..", expected: (windows ? #"\"# : "/"), label: "dot dot path component"),
                (path: "/../../../../..", expected: (windows ? #"\"# : "/"), label: "dot dot path component"),
                (path: "/abc/..", expected: (windows ? #"\"# : "/"), label: "dot dot path component"),
                (path: "/abc/../..", expected: (windows ? #"\"# : "/"), label: "dot dot path component"),
                (path: "/../abc", expected: (windows ? #"\abc"# : "/abc"), label: "dot dot path component"),
                (path: "/../abc/..", expected: (windows ? #"\"# : "/"), label: "dot dot path component"),
                (path: "/../abc/../def", expected: (windows ? #"\def"# : "/def"), label: "dot dot path component"),
                (path: "///", expected: (windows ? #"\"# : "/"), label: "combinations and edge cases"),
                (path: "/./", expected: (windows ? #"\"# : "/"), label: "combinations and edge cases"),
            ]
        )
        func pathStringIsSetCorrectlySkipOnWindows(path: String, expected: String, label: String) {
            withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8511: Path \(path) is not properly") {
                pathStringIsSetCorrectlyTestImplementation(
                    path: path,
                    expected: expected,
                    label: label
                )
            } when :{
                ProcessInfo.hostOperatingSystem == .windows
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

        struct AbsolutePathDirectoryNameAtributeReturnsExpectedValue {
            private func testImplementation(path: String, expected: String) throws {
                let actual = AbsolutePath(path).dirname

                #expect(actual == expected, "Actual is not as expected. Path is: \(path)")
            }

            @Test(
                arguments: [
                    (path: "/", expected: (windows ? #"\"# : "/")),
                    (path: "/a", expected: (windows ? #"\"# : "/")),
                    (path: "/ab/c//d/", expected: (windows ? #"\ab\c"# : "/ab/c")),
                ]
            )
            func absolutePathDirectoryNameAttributeAllPlatforms(path: String, expected: String) throws {
                try testImplementation(path: path, expected: expected)
            }

            @Test(
                .IssueWindowsPathTestsFailures,
                arguments: [
                    (path: "/./a", expected: (windows ? #"\"# : "/")),
                    (path: "/../..", expected: (windows ? #"\"# : "/")),
                ]
            )
            func absolutePathDirectoryNameAttributeFailsOnWindows(path: String, expected: String) throws {
                try withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8511: Path \(path) is not properly") {
                    try testImplementation(path: path, expected: expected)
                } when: {
                    ProcessInfo.hostOperatingSystem == .windows
                }
            }
        }

        struct AbsolutePathBaseNameAttributeReturnsExpectedValue {
            private func testImplementation(path: String, expected: String) throws {
                let actual = AbsolutePath(path).basename

                #expect(actual == expected, "Actual is not as expected: \(path)")
            }

            @Test(
                arguments: [
                    (path: "/", expected: (windows ? #"\"# : "/")),
                    (path: "/a", expected: "a"),
                    (path: "/./a", expected: "a"),
                ]
            )
            func absolutePathBaseNameExtractionAllPlatforms(path: String, expected: String) throws {
                try testImplementation(path: path, expected: expected)
            }

            @Test(
                .IssueWindowsPathTestsFailures,
                arguments: [
                    (path: "/../..", expected: "/"),
                ]
            )
            func absolutePathBaseNameExtractionFailsOnWindows(path: String, expected: String) throws {
                try withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8511: Path \(path) is not properly") {
                    try testImplementation(path: path, expected: expected)
                } when: {
                    ProcessInfo.hostOperatingSystem == .windows
                }
            }
        }

        struct AbsolutePathBasenameWithoutExtAttributeReturnsExpectedValue {
            private func testImplementation(path: String, expected: String) throws {
                let actual = AbsolutePath(path).basenameWithoutExt

                #expect(actual == expected, "Actual is not as expected. Path is: \(path)")
                
            }

            @Test(
                arguments: [
                    (path: "/", expected:  (windows ? #"\"# : "/")),
                    (path: "/a", expected:  "a"),
                    (path: "/./a", expected:  "a"),
                    (path: "/a.txt", expected:  "a"),
                    (path: "/./a.txt", expected:  "a"),
                ]
            )
            func absolutePathBaseNameWithoutExt(path: String, expected: String) throws {
                try testImplementation(path: path, expected: expected)
            }

            @Test(
                .IssueWindowsPathTestsFailures,
                arguments: [
                    (path: "/../..", expected:  "/"),
                ]
            )
            func absolutePathBaseNameWithoutExtFailedOnWindows(path: String, expected: String) throws {
                try withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8511: Path \(path) is not handled properly") {
                    try testImplementation(path: path, expected: expected)
                } when: {
                    ProcessInfo.hostOperatingSystem == .windows
                }
            }
        }

        struct AbsolutePathParentDirectoryAttributeReturnsExpectedValue {
            private func testImplementation(path: String, numParentDirectoryCalls: Int, expected: String) throws {
                let pathUnderTest = AbsolutePath(path)
                let expectedPath = AbsolutePath(expected)
                try #require(numParentDirectoryCalls >= 1, "Test configuration Error.")

                var actual = pathUnderTest
                for _ in 0 ..< numParentDirectoryCalls {
                    actual = actual.parentDirectory
                }
                #expect(actual == expectedPath)
            }
            @Test(
                .IssueWindowsPathTestsFailures,
                arguments: [
                    (path: "/", numParentDirectoryCalls: 1, expected: "/"),
                    (path: "/", numParentDirectoryCalls: 2, expected: "/"),
                    (path: "/bar", numParentDirectoryCalls: 1, expected: "/"),
                ]
            )
            func absolutePathParentDirectoryAttributeReturnsAsExpected(path: String, numParentDirectoryCalls: Int, expected: String) throws {
                try testImplementation(path: path, numParentDirectoryCalls: numParentDirectoryCalls, expected: expected)
            }

            @Test(
                .IssueWindowsPathTestsFailures,
                arguments: [
                    (path: "/bar/../foo/..//", numParentDirectoryCalls: 2, expected: "/"),
                    (path: "/bar/../foo/..//yabba/a/b", numParentDirectoryCalls: 2, expected: "/yabba")
                ]
            )
            func absolutePathParentDirectoryAttributeReturnsAsExpectedFailsOnWindows(path: String, numParentDirectoryCalls: Int, expected: String) throws {
                try withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8511: Path \(path) is not handled properly") {
                    try testImplementation(path: path, numParentDirectoryCalls: numParentDirectoryCalls, expected: expected)
                } when: {
                    ProcessInfo.hostOperatingSystem == .windows
                }
            }

        }

        @Test(
            .IssueWindowsPathTestsFailures,
            arguments: [
                (path: "/", expected: ["/"]),
                (path: "/.", expected: ["/"]),
                (path: "/..", expected: ["/"]),
                (path: "/bar", expected: ["/", "bar"]),
                (path: "/foo/bar/..", expected: ["/", "foo"]),
                (path: "/bar/../foo", expected: ["/", "foo"]),
                (path: "/bar/../foo/..//", expected: ["/"]),
                (path: "/bar/../foo/..//yabba/a/b/", expected: ["/", "yabba", "a", "b"]),
            ]
        )
        func componentsAttributeReturnsExpectedValue(path: String, expected: [String]) throws {
            withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8511: Path \(path) is not handled properly") {
                let actual = AbsolutePath(path).components

                #expect(actual == expected, "Actual is not as expected. Path is: \(path)")
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        struct AncestryTest {
            @Test(
                arguments: [
                    (path: "/a/b/c/d/e/f", descendentOfOrEqualTo: "/a/b/c/d", expected: true),
                    (path: "/a/b/c/d/e/f.swift", descendentOfOrEqualTo: "/a/b/c", expected: true),
                    (path: "/", descendentOfOrEqualTo: "/", expected: true),
                    (path: "/foo/bar", descendentOfOrEqualTo: "/", expected: true),
                    (path: "/foo/bar", descendentOfOrEqualTo: "/foo/bar/baz", expected: false),
                    (path: "/foo/bar", descendentOfOrEqualTo: "/bar", expected: false)
                ]
            )
            func isDescendantOfOrEqual(path: String, descendentOfOrEqualTo: String, expected: Bool) {
                let actual = AbsolutePath(path).isDescendantOfOrEqual(to: AbsolutePath(descendentOfOrEqualTo))

                #expect(actual == expected, "Actual is not as expected. Path is: \(path)")
            }

            @Test(
                arguments: [
                    (path: "/foo/bar", descendentOf: "/foo/bar", expected: false),
                    (path: "/foo/bar", descendentOf: "/foo", expected: true)
                ]
            )
            func isDescendant(path: String, ancesterOf: String, expected: Bool) {
                let actual = AbsolutePath(path).isDescendant(of: AbsolutePath(ancesterOf))

                #expect(actual == expected, "Actual is not as expected. Path is: \(path)")
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

                #expect(actual == expected, "Actual is not as expected. Path is: \(path)")
            }

            @Test(
                arguments: [
                    (path: "/foo/bar", ancesterOf: "/foo/bar", expected: false),
                    (path: "/foo", ancesterOf: "/foo/bar", expected: true),
                ]
            )
            func isAncestor(path: String, ancesterOf: String, expected: Bool) {
                let actual = AbsolutePath(path).isAncestor(of: AbsolutePath(ancesterOf))

                #expect(actual == expected, "Actual is not as expected. Path is: \(path)")
            }
        }

        @Test
        func absolutePathValidation() throws {
            #expect(throws: Never.self) { 
                try AbsolutePath(validating: "/a/b/c/d")
            }

            withKnownIssue {
                #expect {try AbsolutePath(validating: "~/a/b/d")} throws: { error in
                    ("\(error)" == "invalid absolute path '~/a/b/d'; absolute path must begin with '/'")
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }

            #expect {try AbsolutePath(validating: "a/b/d") } throws: { error in
                ("\(error)" == "invalid absolute path 'a/b/d'")
            }
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

    }
    struct RelativePathTests {
        private func pathStringIsSetCorrectlyTestImplementation(path: String, expected: String, label: String) {
            let actual = RelativePath(path).pathString

            #expect(actual == expected, "\(label): Actual is not as expected. Path is: \(path)")
        }

        @Test(
            arguments: [
                (path: ".", expected: ".", label: "Basics"),
                (path: "a", expected: "a", label: "Basics"),
                (path: "a/b/c", expected: (windows ? #"a\b\c"# : "a/b/c"), label: "Basics"),
                (path: "~", expected: "~", label: "Basics"),
                (path: "..", expected: "..", label: "dot dot path component"),
                (path: "", expected:  ".", label: "combinations and edge cases"),
                (path: ".", expected:  ".", label: "combinations and edge cases"),
                (path: "../a", expected:  (windows ? #"..\a"# : "../a"), label: "combinations and edge cases"),
            ]
        )
        func pathStringIsSetCorrectly(path: String, expected: String, label: String) {
            pathStringIsSetCorrectlyTestImplementation(
                path: path,
                expected: expected,
                label: label
            )
        }

        @Test(
            .IssueWindowsPathTestsFailures,
            arguments: [
                (path: "ab//cd//ef", expected: (windows ? #"ab\cd\ef"# : "ab/cd/ef"), label: "repeated path seperators"),
                (path: "ab//cd///ef", expected: (windows ? #"ab\cd\ef"# : "ab/cd/ef"), label: "repeated path seperators"),

                (path: "ab/cd/ef/", expected: (windows ? #"ab\cd\ef"# : "ab/cd/ef"), label: "Trailing path seperator"),
                (path: "ab/cd/ef//", expected: (windows ? #"ab\cd\ef"# : "ab/cd/ef"), label: "Trailing path seperator"),
                (path: "ab/cd/ef///", expected: (windows ? #"ab\cd\ef"# : "ab/cd/ef"), label: "Trailing path seperator"),

                (path: "ab/./cd/././ef", expected: "ab/cd/ef", label: "dot path component"),
                (path: "ab/./cd/ef/.", expected: "ab/cd/ef", label: "dot path component"),

                (path: "../..", expected: "../..", label: "dot dot path component"),
                (path: ".././..", expected: "../..", label: "dot dot path component"),
                (path: "../abc/..", expected: "..", label: "dot dot path component"),
                (path: "../abc/.././", expected: "..", label: "dot dot path component"),
                (path: "abc/..", expected: ".", label: "dot dot path component"),

                (path: "../", expected:  "..", label: "combinations and edge cases"),
                (path: "./abc", expected:  "abc", label: "combinations and edge cases"),
                (path: "./abc/", expected:  "abc", label: "combinations and edge cases"),
                (path: "./abc/../bar", expected:  "bar", label: "combinations and edge cases"),
                (path: "foo/../bar", expected:  "bar", label: "combinations and edge cases"),
                (path: "foo///..///bar///baz", expected:  "bar/baz", label: "combinations and edge cases"),
                (path: "foo/../bar/./", expected:  "bar", label: "combinations and edge cases"),
                (path: "../abc/def/", expected:  "../abc/def", label: "combinations and edge cases"),
                (path: "././././.", expected:  ".", label: "combinations and edge cases"),
                (path: "./././../.", expected:  "..", label: "combinations and edge cases"),
                (path: "./", expected:  ".", label: "combinations and edge cases"),
                (path: ".//", expected:  ".", label: "combinations and edge cases"),
                (path: "./.", expected:  ".", label: "combinations and edge cases"),
                (path: "././", expected:  ".", label: "combinations and edge cases"),
                (path: "../.", expected:  "..", label: "combinations and edge cases"),
                (path: "./..", expected:  "..", label: "combinations and edge cases"),
                (path: "./../.", expected:  "..", label: "combinations and edge cases"),
                (path: "./////../////./////", expected:  "..", label: "combinations and edge cases"),
                (path: "../a/..", expected:  "..", label: "combinations and edge cases"),
                (path: "a/..", expected:  ".", label: "combinations and edge cases"),
                (path: "a/../////../////./////", expected:  "..", label: "combinations and edge cases"),

            ]
        )
        func pathStringIsSetCorrectlyFailsOnWindows(path: String, expected: String, label: String) {
            withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8511: Path \(path) does not resolve properly") {
                    pathStringIsSetCorrectlyTestImplementation(
                    path: path,
                    expected: expected,
                    label: label
                )
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        struct relateivePathDirectoryNameAttributeReturnsExpectedValue {
            private func testImplementation(path: String, expected: String) throws {
                let actual = RelativePath(path).dirname

                #expect(actual == expected, "Actual is not as expected. Path is: \(path)")
            }

            @Test(
                arguments: [
                    (path: "ab/c//d/", expected: (windows ? #"ab\c"# : "ab/c")),
                    (path: "../a", expected: ".."),
                    (path: "./..", expected: "."),
                ]
            )
            func relativePathDirectoryNameExtraction(path: String, expected: String) throws {
                try testImplementation(path: path, expected: expected)
            }

            @Test(
             .IssueWindowsPathTestsFailures,
               arguments: [
                    (path: "../a/..", expected: "."),
                    (path: "a/..", expected: "."),
                    (path: "a/../////../////./////", expected: "."),
                    (path: "abc", expected: "."),
                    (path: "", expected: "."),
                    (path: ".", expected: "."),
                ]
            )
            func relativePathDirectoryNameExtractionFailsOnWindows(path: String, expected: String) throws {
                try withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8511: Path \(path) is not handled properly") {
                    try testImplementation(path: path, expected: expected)
                } when: {
                    ProcessInfo.hostOperatingSystem == .windows
                }
            }

        }

        struct relativePathBaseNameAttributeReturnsExpectedValue {
            private func testImplementation(path: String, expected: String) throws {
                let actual = RelativePath(path).basename

                #expect(actual == expected, "Actual is not as expected. Path is: \(path)")
            }
            @Test(
                arguments: [
                    (path: "../..", expected:  ".."),
                    (path: "../a", expected:  "a"),
                    (path: "../a/..", expected:  ".."),
                    (path: "./..", expected:  ".."),
                    (path: "abc", expected:  "abc"),
                    (path: "", expected:  "."),
                    (path: ".", expected:  "."),
                ]
            )
            func relativePathBaseNameExtraction(path: String, expected: String) throws {
                try testImplementation(path: path, expected: expected)
            }

            @Test(
                .IssueWindowsPathTestsFailures,
                arguments: [
                    (path: "a/..", expected:  "."),
                    (path: "a/../////../////./////", expected:  ".."),
                ]
            )
            func relativePathBaseNameExtractionFailsOnWindows(path: String, expected: String) throws {
                try withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8511: Path \(path) is not handled properly") {
                    try testImplementation(path: path, expected: expected)
                } when: {
                    ProcessInfo.hostOperatingSystem == .windows
                }
            }

        }

        struct RelativePathBasenameWithoutExtAttributeReturnsExpectedValue {
            private func testImplementation(path: String, expected: String) throws {
                let actual: String = RelativePath(path).basenameWithoutExt

                #expect(actual == expected, "Actual is not as expected. Path is: \(path)")
            }

            @Test(
                arguments: [
                    (path: "../a", expected:  "a"),
                    (path: "a/..", expected:  "."),
                    (path: "abc", expected:  "abc"),
                    (path: "../a.bc", expected:  "a"),
                    (path: "abc.swift", expected:  "abc"),
                    (path: "../a.b.c", expected:  "a.b"),
                    (path: "abc.xyz.123", expected:  "abc.xyz"),
                ]
            )
            func relativePathBaseNameWithoutExt(path: String, expected: String) throws {
                try testImplementation(path: path, expected: expected)
            }

            @Test(
            .IssueWindowsPathTestsFailures,
                arguments: [
                    (path: "../..", expected:  ".."),
                    (path: "../a/..", expected:  ".."),
                    (path: "./..", expected:  ".."),
                    (path: "a/../////../////./////", expected:  ".."),
                    (path: "", expected:  "."),
                    (path: ".", expected:  "."),
                ]
            )
            func relativePathBaseNameWithoutExtFailsOnWindows(path: String, expected: String) throws {
                try withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8511: Path \(path) is not properly") {
                    try testImplementation(path: path, expected: expected)
                } when: {
                    ProcessInfo.hostOperatingSystem == .windows
                }
            }

        }

        struct relativePathSuffixAndExtensionAttributeReturnsExpectedValue {
            private func testImplementation(path: String, expectedSuffix: String?, expectedExtension: String?) throws {
                let pathUnderTest = RelativePath(path)

                #expect(pathUnderTest.suffix == expectedSuffix, "Actual suffix is not as expected.  Path is: \(path)")
                #expect(pathUnderTest.extension == expectedExtension, "Actual extension is not as expected.  Path is: \(path)")
            }
            @Test(
                arguments: [
                    (path: "a", expectedSuffix: nil, expectedExtension: nil),
                    (path: "a.foo", expectedSuffix: ".foo", expectedExtension: "foo"),
                    (path: ".a.foo", expectedSuffix: ".foo", expectedExtension: "foo"),
                    (path: "a.foo.bar", expectedSuffix: ".bar", expectedExtension: "bar"),
                    (path: ".a.foo.bar", expectedSuffix: ".bar", expectedExtension: "bar"),
                    (path: ".a.foo.bar.baz", expectedSuffix: ".baz", expectedExtension: "baz"),
                ]
            )
            func suffixExtraction(path: String, expectedSuffix: String?, expectedExtension: String?) throws {
                try testImplementation(path: path, expectedSuffix: expectedSuffix, expectedExtension: expectedExtension)
            }

            @Test(
             .IssueWindowsPathTestsFailures,
               arguments:[
                    "a.",
                    ".a",
                    "",
                    ".",
                    "..",
                ]
            )
            func suffixExtractionFailsOnWindows(path: String) throws {
                try withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8511: Path \(path) is not handled properly") {
                    try testImplementation(path: path, expectedSuffix: nil, expectedExtension: nil)
                } when: {
                    ProcessInfo.hostOperatingSystem == .windows
                }
            }

        }

        struct componentsAttributeReturnsExpectedValue {
            private func testImplementation(path: String, expected: [String]) throws {
                let actual = RelativePath(path).components

                #expect(actual == expected, "Actual is not as expected: \(path)")
            }

            @Test(
                arguments: [
                    (path: "", expected: ["."]),
                    (path: ".", expected: ["."]),
                    (path: "..", expected: [".."]),
                    (path: "bar", expected: ["bar"]),
                    (path: "../..", expected: ["..", ".."]),
                    (path: "../a", expected: ["..", "a"]),
                    (path: "abc", expected: ["abc"]),
                ] as [(String, [String])]
            )
            func relativePathComponentsAttributeAllPlatform(path: String, expected: [String]) throws {
                try testImplementation(path: path, expected: expected)
            }

            @Test(
            .IssueWindowsPathTestsFailures,
                arguments: [
                    (path: "foo/bar/..", expected: ["foo"]),
                    (path: "bar/../foo", expected: ["foo"]),
                    (path: "bar/../foo/..//", expected: ["."]),
                    (path: "bar/../foo/..//yabba/a/b/", expected: ["yabba", "a", "b"]),
                    (path: ".././/..", expected: ["..", ".."]),
                    (path: "../a/..", expected: [".."]),
                    (path: "a/..", expected: ["."]),
                    (path: "./..", expected: [".."]),
                    (path: "a/../////../////./////", expected: [".."]),
                ] as [(String, [String])]
            )
            func relativePathComponentsAttributeFailsOnWindows(path: String, expected: [String]) throws {
                try withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8511: Path \(path) is not properly") {
                    try testImplementation(path: path, expected: expected)
                } when: {
                    ProcessInfo.hostOperatingSystem == .windows
                }
            }
        }
        
        @Test(
            .IssueWindowsPathTestsFailures,
        )
        func relativePathValidation() throws {
            #expect(throws: Never.self) { 
                try RelativePath(validating: "a/b/c/d")
            }

            withKnownIssue("https://github.com/swiftlang/swift-package-manager/issues/8511: \\") {
                #expect {try RelativePath(validating: "/a/b/d")} throws: { error in
                    ("\(error)" == "invalid relative path '/a/b/d'; relative path should not begin with '/'")
                }
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }
    }

    @Test
    @available(*, deprecated)
    func concatenation() throws {
        #expect(AbsolutePath(AbsolutePath("/"), RelativePath("")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath(AbsolutePath("/"), RelativePath(".")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath(AbsolutePath("/"), RelativePath("..")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath(AbsolutePath("/"), RelativePath("bar")).pathString == (windows ? #"\bar"# : "/bar"))
        #expect(AbsolutePath(AbsolutePath("/foo/bar"), RelativePath("..")).pathString == (windows ? #"\foo"# : "/foo"))
        #expect(AbsolutePath(AbsolutePath("/bar"), RelativePath("../foo")).pathString == (windows ? #"\foo"# : "/foo"))
        withKnownIssue {
            #expect(AbsolutePath(AbsolutePath("/bar"), RelativePath("../foo/..//")).pathString == (windows ? #"\"# : "/"))
            #expect(AbsolutePath(AbsolutePath("/bar/../foo/..//yabba/"), RelativePath("a/b")).pathString == (windows ? #"\yabba\a\b"# : "/yabba/a/b"))
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }

        #expect(AbsolutePath("/").appending(RelativePath("")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath("/").appending(RelativePath(".")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath("/").appending(RelativePath("..")).pathString == (windows ? #"\"# : "/"))
        #expect(AbsolutePath("/").appending(RelativePath("bar")).pathString == (windows ? #"\bar"# : "/bar"))
        #expect(AbsolutePath("/foo/bar").appending(RelativePath("..")).pathString == (windows ? #"\foo"# : "/foo"))
        #expect(AbsolutePath("/bar").appending(RelativePath("../foo")).pathString == (windows ? #"\foo"# : "/foo"))
        withKnownIssue {
            #expect(AbsolutePath("/bar").appending(RelativePath("../foo/..//")).pathString == (windows ? #"\"# : "/"))
            #expect(AbsolutePath("/bar/../foo/..//yabba/").appending(RelativePath("a/b")).pathString == (windows ? #"\yabba\a\b"# : "/yabba/a/b"))
        } when: {
            ProcessInfo.hostOperatingSystem == .windows
        }

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
    func relativePathFromAbsolutePaths() throws {
        #expect(AbsolutePath("/").relative(to: AbsolutePath("/")) == RelativePath("."));
        #expect(AbsolutePath("/a/b/c/d").relative(to: AbsolutePath("/")) == RelativePath("a/b/c/d"));
        #expect(AbsolutePath("/").relative(to: AbsolutePath("/a/b/c")) == RelativePath("../../.."));
        #expect(AbsolutePath("/a/b/c/d").relative(to: AbsolutePath("/a/b")) == RelativePath("c/d"));
        #expect(AbsolutePath("/a/b/c/d").relative(to: AbsolutePath("/a/b/c")) == RelativePath("d"));
        #expect(AbsolutePath("/a/b/c/d").relative(to: AbsolutePath("/a/c/d")) == RelativePath("../../b/c/d"));
        #expect(AbsolutePath("/a/b/c/d").relative(to: AbsolutePath("/b/c/d")) == RelativePath("../../../a/b/c/d"));
    }

    @Test
    func codable() throws {
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
            #expect(foo == decodedFoo)
        }

        do {
            let foo = Foo(path: "/path/to/../to/foo")
            let data = try JSONEncoder().encode(foo)
            let decodedFoo = try JSONDecoder().decode(Foo.self, from: data)
            #expect(foo == decodedFoo)
            withKnownIssue {
                #expect(foo.path.pathString == (windows ? #"\path\to\foo"# : "/path/to/foo"))
                #expect(decodedFoo.path.pathString == (windows ? #"\path\to\foo"# : "/path/to/foo"))
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        do {
            let bar = Bar(path: "path/to/bar")
            let data = try JSONEncoder().encode(bar)
            let decodedBar = try JSONDecoder().decode(Bar.self, from: data)
            #expect(bar == decodedBar)
        }

        do {
            let bar = Bar(path: "path/to/../to/bar")
            let data = try JSONEncoder().encode(bar)
            let decodedBar = try JSONDecoder().decode(Bar.self, from: data)
            #expect(bar == decodedBar)
            withKnownIssue {
                #expect(bar.path.pathString == "path/to/bar")
                #expect(decodedBar.path.pathString == "path/to/bar")
            } when: {
                ProcessInfo.hostOperatingSystem == .windows
            }
        }

        do {
            let data = try JSONEncoder().encode(Baz(path: ""))
            #expect(throws: (any Error).self) { 
                try JSONDecoder().decode(Foo.self, from: data)
            }
            #expect(throws: Never.self) { 
                try JSONDecoder().decode(Bar.self, from: data)
            } // empty string is a valid relative path
        }

        do {
            let data = try JSONEncoder().encode(Baz(path: "foo"))
            #expect(throws: (any Error).self) { 
                try JSONDecoder().decode(Foo.self, from: data)
            }
        }

        do {
            let data = try JSONEncoder().encode(Baz(path: "/foo"))
            #expect(throws: (any Error).self) { 
                try JSONDecoder().decode(Bar.self, from: data)
            }
        }
    }

    // FIXME: We also need tests for join() operations.

    // FIXME: We also need tests for dirname, basename, suffix, etc.

    // FIXME: We also need test for stat() operations.
}
