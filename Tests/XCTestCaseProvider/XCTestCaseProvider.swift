/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
 XCTestCaseProvider is defined on Linux as part of swift-corelibs-xctest,
 but is not available on OS X.

 By defining this protocol on OS X, we ensure that the tests contributed
 by people developing on OS X still conform to XCTestCaseProvider, which
 is necessary for running those tests on Linux.
 */

// Ensure that these re-definitions of XCTestCaseProvider and XCTMain
// are not used on Linux, where it is already defined by
// swift-corelibs-xctest.
#if os(OSX)
    public protocol XCTestCaseProvider {
        var allTests : [(String, () -> Void)] { get }
    }

    public func XCTMain(testCases: [XCTestCaseProvider]) {
        fatalError("Unreachable.")
    }
#endif
