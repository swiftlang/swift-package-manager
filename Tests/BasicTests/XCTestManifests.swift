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
        testCase(ByteStringTests.allTests),
        testCase(CollectionAlgorithmsTests.allTests),
        testCase(ConditionTests.allTests),
        testCase(DictionaryExtensionTests.allTests),
        testCase(FileAccessTests.allTests),
        testCase(FileSystemTests.allTests),
        testCase(GraphAlgorithmsTests.allTests),
        testCase(JSONTests.allTests),
        testCase(KeyedPairTests.allTests),
        testCase(LazyCacheTests.allTests),
        testCase(LockTests.allTests),
        testCase(OptionParserTests.allTests),
        testCase(OrderedSetTests.allTests),
        testCase(OutputByteStreamTests.allTests),
        testCase(POSIXTests.allTests),
        testCase(PathShimTests.allTests),
        testCase(PathTests.allTests),
        testCase(StringConversionTests.allTests),
        testCase(SyncronizedQueueTests.allTests),
        testCase(TemporaryFileTests.allTests),
        testCase(TerminalControllerTests.allTests),
        testCase(ThreadTests.allTests),
        testCase(WalkTests.allTests),
    ]
}
#endif
