//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import _InternalTestSupport
import Testing

fileprivate struct URLOriginTests {
    @Test(arguments: [
        (URL("https://example.com/one"), URL("https://example.com/two")),
        (URL("https://example.com"), URL("https://example.com/deep/path?query=1#fragment")),
        (URL("https://EXAMPLE.com/one"), URL("https://example.COM/two")),
        (URL("HTTPS://example.com/one"), URL("https://example.com/two")),
        (URL("https://example.com:443/one"), URL("https://example.com/two")),
        (URL("http://example.com:80/one"), URL("http://example.com/two")),
        (URL("https://example.com:8443/one"), URL("https://example.com:8443/two")),
    ])
    func sameOrigin(_ lhs: URL, _ rhs: URL) {
        #expect(lhs.hasSameOrigin(as: rhs))
        #expect(rhs.hasSameOrigin(as: lhs))
    }

    @Test(arguments: [
        (URL("https://example.com/one"), URL("https://cdn.example.com/one")),
        (URL("https://example.com/one"), URL("https://example.com.evil.test/one")),
        (URL("https://example.com/one"), URL("http://example.com/one")),
        (URL("https://example.com/one"), URL("https://example.com:8443/one")),
        (URL("http://example.com/one"), URL("http://example.com:8080/one")),
        (URL("https://example.com/one"), URL("file:///example.com/one")),
    ])
    func differentOrigin(_ lhs: URL, _ rhs: URL) {
        #expect(!lhs.hasSameOrigin(as: rhs))
        #expect(!rhs.hasSameOrigin(as: lhs))
    }

    @Test
    func hostlessURLsNeverShareAnOrigin() {
        let hostless = URL("file:///tmp/archive.zip")
        #expect(!hostless.hasSameOrigin(as: hostless))
    }
}
