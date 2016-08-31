/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

#if !os(macOS)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(ConventionTests.allTests),
        testCase(JSONSerializationTests.allTests),
        testCase(ManifestTests.allTests),
        testCase(ModuleDependencyTests.allTests),
        testCase(ModuleMapGeneration.allTests),
        testCase(SerializationTests.allTests),
        testCase(PkgConfigWhitelistTests.allTests),
    ]
}
#endif

