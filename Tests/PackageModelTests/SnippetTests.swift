//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import PackageModel
import Testing

@Suite(
    .tags(
        .TestSize.small,
        .Feature.Snippets,
    ),
)
struct SnippetTests {
    let fakeSourceFilePath = AbsolutePath("/fake/path/to/test.swift")

    /// Test the contents of the ``Snippet`` model when parsing an empty file.
    /// Currently, no errors are emitted and most things are either nil or empty.
    @Test
    func testEmptySourceFile() async throws {
        let source = ""
        let snippet = Snippet(parsing: source, path: fakeSourceFilePath)
        #expect(snippet.path == fakeSourceFilePath)
        #expect(snippet.explanation.isEmpty)
        #expect(snippet.presentationCode.isEmpty)
        #expect(snippet.groupName == nil)
        #expect("test" == snippet.name)
    }

    /// Test the contents of the ``Snippet`` model when parsing a typical
    /// source file.
    @Test
    func testBasic() async throws {
        let explanation = "This snippet does a foo. Try it when XYZ."
        let presentationCode = """
        import Module

        func foo(x: X) {}
        """

        let source = """

        //! \(explanation)

        \(presentationCode)

        // MARK: HIDE

        print(foo(x: x()))
        """

        let snippet = Snippet(parsing: source, path: fakeSourceFilePath)

        #expect(snippet.path == fakeSourceFilePath)
        #expect(explanation == snippet.explanation)
        #expect(presentationCode == snippet.presentationCode)
        #expect(snippet.groupName == nil)
        #expect("test" == snippet.name)
    }

    /// Test that multiple consecutive newlines in a snippet's
    /// presentation code is coalesced into no more than two newlines,
    /// and test that newlines at the beginning and end of are stripped.
    @Test
    func testMultiNewlineCoalescing() async throws {
        let explanation = "This snippet does a foo. Try it when XYZ."
        let presentationCode = """


        import Module




        func foo(x: X) {}


        """

        let source = """

        //!
        //! \(explanation)
        //!

        \(presentationCode)

        // MARK: HIDE

        print(foo(x: x()))
        """

        let expectedPresentationCode = """
        import Module

        func foo(x: X) {}
        """

        let snippet = Snippet(parsing: source, path: fakeSourceFilePath)
        #expect(explanation == snippet.explanation)
        #expect(expectedPresentationCode == snippet.presentationCode)
    }

    /// Test that toggling back and forth with `mark: hide` and `mark: show`
    /// works as intended.
    func testMarkHideShowToggle() async throws {
        let source = """
        shown1

        // mark: hide
        hidden1

        // mark: show
        shown2

        // mark: hide
        hidden2

        // mark: show
        shown3
        """

        let expectedPresentationCode = """
        shown1

        shown2
        
        shown3
        """

        let snippet = Snippet(parsing: source, path: fakeSourceFilePath)
        #expect(!snippet.presentationCode.contains("hidden"))
        #expect(!snippet.explanation.contains("hidden"))
        #expect(expectedPresentationCode == snippet.presentationCode)
    }

    /// Tests that extra indentation is removed when extracting some inner
    /// part of nested code.
    @Test
    func testRemoveExtraIndentation() async throws {
        let source = """
        // mark: hide
        struct Outer {
          struct Inner {
            // mark: show
            struct InnerInner {
            }
            // mark: hide
          }
        }
        """

        let expectedPresentationCode = """
        struct InnerInner {
        }
        """
        let snippet = Snippet(parsing: source, path: fakeSourceFilePath)
        #expect(expectedPresentationCode == snippet.presentationCode)
    }
}
