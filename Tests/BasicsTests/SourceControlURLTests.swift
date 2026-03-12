//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Testing

@Suite("SourceControlURL")
struct SourceControlURLTests {
    @Test func validURLs() {
        #expect(SourceControlURL("https://github.com/owner/repo").isValid)
        #expect(SourceControlURL("https://github.com/owner/repo.git").isValid)
        #expect(SourceControlURL("git@github.com:owner/repo.git").isValid)
        #expect(SourceControlURL("ssh://git@github.com/owner/repo.git").isValid)
        #expect(SourceControlURL("http://example.com/path/to/repo").isValid)
    }

    @Test func invalidURLs_withWhitespace() {
        // URLs containing whitespace are invalid (typically indicates concatenated error messages)
        #expect(!SourceControlURL("https://github.com/owner/repo.git': failed looking up identity").isValid)
        #expect(!SourceControlURL("https://github.com/owner/repo error message").isValid)
        #expect(!SourceControlURL("https://github.com/owner/repo\there").isValid)
        #expect(!SourceControlURL("https://github.com/owner/repo\nhere").isValid)
    }

    @Test func invalidURLs_unparseable() {
        // URLs that can't be parsed
        #expect(!SourceControlURL("not a url").isValid)
        #expect(!SourceControlURL("").isValid)
    }

    @Test func invalidURLs_noHost() {
        // URLs without a host
        #expect(!SourceControlURL("file:///path/to/repo").isValid)
    }
}
