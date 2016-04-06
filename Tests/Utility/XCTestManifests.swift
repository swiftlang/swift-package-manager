/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

extension CollectionTests {
    static var allTests : [(String, CollectionTests -> () throws -> Void)] {
        return [
                   ("testPick", testPick),
                   ("testPartitionByType", testPartitionByType),
                   ("testPartitionByClosure", testPartitionByClosure),
                   ("testSplitAround", testSplitAround)
        ]
    }
}

extension FileTests {
    static var allTests : [(String, FileTests -> () throws -> Void)] {
        return [
                   ("testOpenFile", testOpenFile),
                   ("testOpenFileFail", testOpenFileFail),
                   ("testReadRegularTextFile", testReadRegularTextFile),
                   ("testReadRegularTextFileWithSeparator", testReadRegularTextFileWithSeparator)
        ]
    }
}


extension RmtreeTests {
    static var allTests : [(String, RmtreeTests -> () throws -> Void)] {
        return [
                   ("testDoesNotFollowSymlinks", testDoesNotFollowSymlinks),
        ]
    }
}

extension PathTests {
    static var allTests : [(String, PathTests -> () throws -> Void)] {
        return [
                   ("test", test),
                   ("testPrecombined", testPrecombined),
                   ("testExtraSeparators", testExtraSeparators),
                   ("testEmpties", testEmpties),
                   ("testNormalizePath", testNormalizePath),
                   ("testJoinWithAbsoluteReturnsLastAbsoluteComponent", testJoinWithAbsoluteReturnsLastAbsoluteComponent),
                   ("testParentDirectory", testParentDirectory),
        ]
    }
}

extension WalkTests {
    static var allTests : [(String, WalkTests -> () throws -> Void)] {
        return [
                   ("testNonRecursive", testNonRecursive),
                   ("testRecursive", testRecursive),
                   ("testSymlinksNotWalked", testSymlinksNotWalked),
                   ("testWalkingADirectorySymlinkResolvesOnce", testWalkingADirectorySymlinkResolvesOnce),
        ]
    }
}

extension StatTests {
    static var allTests : [(String, StatTests -> () throws -> Void)] {
        return [
                   ("test_isdir", test_isdir),
                   ("test_isfile", test_isfile),
                   ("test_realpath", test_realpath),
                   ("test_basename", test_basename),
        ]
    }
}

extension RelativePathTests {
    static var allTests : [(String, RelativePathTests -> () throws -> Void)] {
        return [
                   ("testAbsolute", testAbsolute),
                   ("testRelative", testRelative),
                   ("testMixed", testMixed),
                   ("testRelativeCommonSubprefix", testRelativeCommonSubprefix),
                   ("testCombiningRelativePaths", testCombiningRelativePaths)
        ]
    }
}

extension ShellTests {
    static var allTests : [(String, ShellTests -> () throws -> Void)] {
        return [
                   ("testPopen", testPopen),
                   ("testPopenWithBufferLargerThanThatAllocated", testPopenWithBufferLargerThanThatAllocated),
                   ("testPopenWithBinaryOutput", testPopenWithBinaryOutput)
        ]
    }
}


extension StringTests {
    static var allTests : [(String, StringTests -> () throws -> Void)] {
        return [
                   ("testTrailingChomp", testTrailingChomp),
                   ("testEmptyChomp", testEmptyChomp),
                   ("testSeparatorChomp", testSeparatorChomp),
                   ("testChuzzle", testChuzzle),
                   ("testSplitAround", testSplitAround)
        ]
    }
    
}

extension URLTests {
    static var allTests : [(String, URLTests -> () throws -> Void)] {
        return [
                   ("testSchema", testSchema),
        ]
    }
}
