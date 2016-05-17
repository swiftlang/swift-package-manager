/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

#if !os(OSX)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(JSONSerializationTests.allTests),
        testCase(ManifestTests.allTests),
        testCase(SerializationTests.allTests),
    ]
}
#endif

