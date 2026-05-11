//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import Testing

struct PathShimTests {
    @Test
    func rescursiveDirectoryCreation() {
        try! withTemporaryDirectory(removeTreeOnDeinit: true) { path in
            // Create a directory under several ancestor directories.
            let dirPath = path.appending(components: "abc", "def", "ghi", "mno", "pqr")
            try! makeDirectories(dirPath)

            // Check that we were able to actually create the directory.
            #expect(localFileSystem.isDirectory(dirPath))

            // Check that there's no error if we try to create the directory again.
            #expect(throws: Never.self) {
                try! makeDirectories(dirPath)
            }
        }
    }
}

struct WalkTests {
    @Test
    func nonRecursive() throws {
        #if os(Android)
            let root = "/system"
            var expected: [AbsolutePath] = [
                "\(root)/usr",
                "\(root)/bin",
                "\(root)/etc",
            ]
            let expectedCount = 3
        #elseif os(Windows)
            let root = ProcessInfo.processInfo.environment["SystemRoot"]!
            var expected: [AbsolutePath] = [
                "\(root)/System32",
                "\(root)/SysWOW64",
            ]
            let expectedCount = (root as NSString).pathComponents.count + 2
        #else
            let root = ""
            var expected: [AbsolutePath] = [
                "/usr",
                "/bin",
                "/sbin",
            ]
            let expectedCount = 2
        #endif
        for x in try walk(AbsolutePath(validating: "\(root)/"), recursively: false) {
            if let i = expected.firstIndex(of: x) {
                expected.remove(at: i)
            }
            #expect(x.components.count == expectedCount, "Actual is not as expected")
        }
        #expect(expected.count == 0)
    }

    @Test
    func recursive() {
        let root = AbsolutePath(#file).parentDirectory.parentDirectory.parentDirectory.parentDirectory
            .appending(component: "Sources")
        var expected = [
            root.appending(component: "Basics"),
            root.appending(component: "Build"),
            root.appending(component: "Commands"),
        ]
        for x in try! walk(root) {
            if let i = expected.firstIndex(of: x) {
                expected.remove(at: i)
            }
        }
        #expect(expected == [])
    }
}
