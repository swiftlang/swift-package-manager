//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import XCTest
import _InternalTestSupport

class CommandsTestCase: XCTestCase {
    
    /// Original working directory before the test ran (if known).
    private var originalWorkingDirectory: AbsolutePath? = .none
    public let duplicateSymbolRegex = StringPattern.regex(
        #"objc[83768]: (.*) is implemented in both .* \(.*\) and .* \(.*\) . One of the two will be used. Which one is undefined."#
    )

    override func setUp() {
        originalWorkingDirectory = localFileSystem.currentWorkingDirectory
    }
    
    override func tearDown() {
        if let originalWorkingDirectory {
            try? localFileSystem.changeCurrentWorkingDirectory(to: originalWorkingDirectory)
        }
    }
    
    // FIXME: We should also hoist the `execute()` helper function that the various test suites implement, but right now they all seem to have slightly different implementations, so that's a later project.
}

class CommandsBuildProviderTestCase: BuildSystemProviderTestCase {
    /// Original working directory before the test ran (if known).
    private var originalWorkingDirectory: AbsolutePath? = .none
    let duplicateSymbolRegex = StringPattern.regex(".*One of the duplicates must be removed or renamed.")

    override func setUp() {
        originalWorkingDirectory = localFileSystem.currentWorkingDirectory
    }

    override func tearDown() {
        if let originalWorkingDirectory {
            try? localFileSystem.changeCurrentWorkingDirectory(to: originalWorkingDirectory)
        }
    }

    // FIXME: We should also hoist the `execute()` helper function that the various test suites implement, but right now they all seem to have slightly different implementations, so that's a later project.
}
