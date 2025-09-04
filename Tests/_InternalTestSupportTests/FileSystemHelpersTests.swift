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
import _InternalTestSupport
import Testing

@Suite(
    .tags(
        .TestSize.small,
    ),
)
struct FileSystemHelpersTests {
    @Test("getFiles with AbsolutePath - recursive")
    func testGetFilesAbsolutePathRecursive() throws {
        // Create an in-memory file system for testing
        let fileSystem = InMemoryFileSystem()
        
        // Create a test directory structure
        let testDir = try AbsolutePath(validating: "/test")
        try fileSystem.createDirectory(testDir, recursive: true)
        
        // Create some test files
        let swiftFile1 = testDir.appending("file1.swift")
        let swiftFile2 = testDir.appending("subdir").appending("file2.swift")
        let txtFile = testDir.appending("readme.txt")
        let swiftFile3 = testDir.appending("subdir").appending("nested").appending("file3.swift")
        
        try fileSystem.createDirectory(swiftFile2.parentDirectory, recursive: true)
        try fileSystem.createDirectory(swiftFile3.parentDirectory, recursive: true)
        
        try fileSystem.writeFileContents(swiftFile1, string: "// Swift file 1")
        try fileSystem.writeFileContents(swiftFile2, string: "// Swift file 2")
        try fileSystem.writeFileContents(txtFile, string: "This is a text file")
        try fileSystem.writeFileContents(swiftFile3, string: "// Swift file 3")
        
        // Test recursive search (default)
        let swiftFiles = try getFiles(
            in: testDir,
            matchingExtension: "swift",
            fileSystem: fileSystem
        )
        
        // Verify results
        #expect(swiftFiles.count == 3)
        #expect(swiftFiles.contains(swiftFile1))
        #expect(swiftFiles.contains(swiftFile2))
        #expect(swiftFiles.contains(swiftFile3))
        #expect(!swiftFiles.contains(txtFile))
        
        // Test with different extension
        let txtFiles = try getFiles(
            in: testDir,
            matchingExtension: "txt",
            fileSystem: fileSystem
        )
        
        #expect(txtFiles.count == 1)
        #expect(txtFiles.contains(txtFile))
    }
    
    @Test("getFiles with AbsolutePath - non-recursive")
    func testGetFilesAbsolutePathNonRecursive() throws {
        let fileSystem = InMemoryFileSystem()
        
        let testDir = try AbsolutePath(validating: "/test")
        try fileSystem.createDirectory(testDir, recursive: true)
        
        // Create files at different levels
        let swiftFile1 = testDir.appending("file1.swift")
        let swiftFile2 = testDir.appending("subdir").appending("file2.swift")
        
        try fileSystem.createDirectory(swiftFile2.parentDirectory, recursive: true)
        try fileSystem.writeFileContents(swiftFile1, string: "// Swift file 1")
        try fileSystem.writeFileContents(swiftFile2, string: "// Swift file 2")
        
        // Test non-recursive search
        let swiftFiles = try getFiles(
            in: testDir,
            matchingExtension: "swift",
            recursive: false,
            fileSystem: fileSystem
        )
        
        // Should only find the top-level file
        #expect(swiftFiles.count == 1)
        #expect(swiftFiles.contains(swiftFile1))
        #expect(!swiftFiles.contains(swiftFile2))
    }
    
    @Test("getFiles with case insensitive extension matching")
    func testGetFilesCaseInsensitive() throws {
        let fileSystem = InMemoryFileSystem()
        
        let testDir = try AbsolutePath(validating: "/test")
        try fileSystem.createDirectory(testDir, recursive: true)
        
        // Create files with different case extensions
        let swiftFile = testDir.appending("file1.swift")
        let SwiftFile = testDir.appending("file2.Swift")
        let SWIFTFile = testDir.appending("file3.SWIFT")
        
        try fileSystem.writeFileContents(swiftFile, string: "// file1")
        try fileSystem.writeFileContents(SwiftFile, string: "// file2")
        try fileSystem.writeFileContents(SWIFTFile, string: "// file3")
        
        // Test with lowercase extension
        let results = try getFiles(
            in: testDir,
            matchingExtension: "swift",
            fileSystem: fileSystem
        )
        
        #expect(results.count == 3)
        #expect(results.contains(swiftFile))
        #expect(results.contains(SwiftFile))
        #expect(results.contains(SWIFTFile))
    }
    
    @Test("getFiles with non-existent directory")
    func testGetFilesNonExistentDirectory() throws {
        let fileSystem = InMemoryFileSystem()
        let nonExistentDir = try AbsolutePath(validating: "/nonexistent")
        
        #expect(throws: StringError.self) {
            try getFiles(
                in: nonExistentDir,
                matchingExtension: "swift",
                fileSystem: fileSystem
            )
        }
    }
    
    @Test("getFiles with file instead of directory")
    func testGetFilesWithFile() throws {
        let fileSystem = InMemoryFileSystem()
        
        let testFile = try AbsolutePath(validating: "/test.swift")
        try fileSystem.writeFileContents(testFile, string: "// test file")
        
        #expect(throws: StringError.self) {
            try getFiles(
                in: testFile,
                matchingExtension: "swift",
                fileSystem: fileSystem
            )
        }
    }
    
    @Test("getFiles with empty directory")
    func testGetFilesEmptyDirectory() throws {
        let fileSystem = InMemoryFileSystem()
        
        let testDir = try AbsolutePath(validating: "/empty")
        try fileSystem.createDirectory(testDir, recursive: true)
        
        let results = try getFiles(
            in: testDir,
            matchingExtension: "swift",
            fileSystem: fileSystem
        )
        
        #expect(results.isEmpty)
    }
    
    @Test("getFiles with RelativePath - non-recursive")
    func testGetFilesRelativePathNonRecursive() throws {
        let fileSystem = InMemoryFileSystem()
        
        // Set up current working directory
        let cwd = try AbsolutePath(validating: "/current")
        try fileSystem.createDirectory(cwd, recursive: true)
        try fileSystem.changeCurrentWorkingDirectory(to: cwd)
        
        // Create test directory structure
        let testDir = try RelativePath(validating: "test")
        let absoluteTestDir = cwd.appending(testDir)
        try fileSystem.createDirectory(absoluteTestDir, recursive: true)
        
        // Create files at different levels
        let swiftFile1 = absoluteTestDir.appending("file1.swift")
        let swiftFile2 = absoluteTestDir.appending("subdir").appending("file2.swift")
        
        try fileSystem.createDirectory(swiftFile2.parentDirectory, recursive: true)
        try fileSystem.writeFileContents(swiftFile1, string: "// Swift file 1")
        try fileSystem.writeFileContents(swiftFile2, string: "// Swift file 2")
        
        // Test non-recursive search
        let swiftFiles = try getFiles(
            in: testDir,
            matchingExtension: "swift",
            recursive: false,
            fileSystem: fileSystem
        )
        
        // Should only find the top-level file
        #expect(swiftFiles.count == 1)
        
        let expectedFile1 = swiftFile1.relative(to: cwd)
        #expect(swiftFiles.contains(expectedFile1))
        
        // Should not find the nested file
        let expectedFile2 = swiftFile2.relative(to: cwd)
        #expect(!swiftFiles.contains(expectedFile2))
    }
    
    @Test("getFiles with RelativePath - invalid path")
    func testGetFilesRelativePathInvalid() throws {
        let fileSystem = InMemoryFileSystem()
        
        // Set up current working directory
        let cwd = try AbsolutePath(validating: "/current")
        try fileSystem.createDirectory(cwd, recursive: true)
        try fileSystem.changeCurrentWorkingDirectory(to: cwd)
        
        // Try to access non-existent relative directory
        let nonExistentDir = try RelativePath(validating: "nonexistent")
        
        #expect(throws: StringError.self) {
            try getFiles(
                in: nonExistentDir,
                matchingExtension: "swift",
                fileSystem: fileSystem
            )
        }
    }
    
    @Test("getFiles with RelativePath - file instead of directory")
    func testGetFilesRelativePathWithFile() throws {
        let fileSystem = InMemoryFileSystem()
        
        // Set up current working directory
        let cwd = try AbsolutePath(validating: "/current")
        try fileSystem.createDirectory(cwd, recursive: true)
        try fileSystem.changeCurrentWorkingDirectory(to: cwd)
        
        // Create a file instead of directory
        let testFile = cwd.appending("test.swift")
        try fileSystem.writeFileContents(testFile, string: "// test file")
        
        let relativeFile = try RelativePath(validating: "test.swift")
        
        #expect(throws: StringError.self) {
            try getFiles(
                in: relativeFile,
                matchingExtension: "swift",
                fileSystem: fileSystem
            )
        }
    }
    
    @Test("getFiles with RelativePath - no current working directory")
    func testGetFilesRelativePathNoCwd() throws {
        let fileSystem = InMemoryFileSystem()
        // Don't set a current working directory
        
        let testDir = try RelativePath(validating: "test")
        
        #expect(throws: StringError.self) {
            try getFiles(
                in: testDir,
                matchingExtension: "swift",
                fileSystem: fileSystem
            )
        }
    }
    
    @Test("getFiles with RelativePath - complex nested structure")
    func testGetFilesRelativePathComplexStructure() throws {
        let fileSystem = InMemoryFileSystem()
        
        // Set up current working directory
        let cwd = try AbsolutePath(validating: "/project")
        try fileSystem.createDirectory(cwd, recursive: true)
        try fileSystem.changeCurrentWorkingDirectory(to: cwd)
        
        // Create complex directory structure
        let sourcesDir = try RelativePath(validating: "Sources")
        let absoluteSourcesDir = cwd.appending(sourcesDir)
        try fileSystem.createDirectory(absoluteSourcesDir, recursive: true)
        
        // Create files in various subdirectories
        let files = [
            "Sources/App/main.swift",
            "Sources/App/Models/User.swift",
            "Sources/App/Controllers/UserController.swift",
            "Sources/Shared/Utils.swift",
            "Sources/Shared/Extensions/String+Extensions.swift",
            "Sources/Tests/AppTests.swift",
            "Sources/README.md", // Non-Swift file
        ]
        
        for filePath in files {
            let absolutePath = try AbsolutePath(validating: filePath, relativeTo: cwd)
            try fileSystem.createDirectory(absolutePath.parentDirectory, recursive: true)
            try fileSystem.writeFileContents(absolutePath, string: "// \(absolutePath.basename)")
        }
        
        // Test recursive search
        let allSwiftFiles = try getFiles(
            in: sourcesDir,
            matchingExtension: "swift",
            fileSystem: fileSystem
        )
        
        #expect(allSwiftFiles.count == 6) // All .swift files, excluding README.md
        
        // Verify all expected files are found
        let expectedSwiftFiles = files.filter { $0.hasSuffix(".swift") }
        for expectedFile in expectedSwiftFiles {
            let relativePath = try RelativePath(validating: expectedFile)
            #expect(allSwiftFiles.contains(relativePath))
        }
        
        // Test non-recursive search (should find no files at Sources root level)
        let topLevelSwiftFiles = try getFiles(
            in: sourcesDir,
            matchingExtension: "swift",
            recursive: false,
            fileSystem: fileSystem
        )
        
        #expect(topLevelSwiftFiles.isEmpty)
    }
    
    @Test("getFiles with RelativePath - case sensitivity validation")
    func testGetFilesRelativePathCaseSensitivity() throws {
        let fileSystem = InMemoryFileSystem()
        
        // Set up current working directory
        let cwd = try AbsolutePath(validating: "/test")
        try fileSystem.createDirectory(cwd, recursive: true)
        try fileSystem.changeCurrentWorkingDirectory(to: cwd)
        
        // Create test directory
        let testDir = try RelativePath(validating: "files")
        let absoluteTestDir = cwd.appending(testDir)
        try fileSystem.createDirectory(absoluteTestDir, recursive: true)
        
        // Create files with different case extensions
        let files = [
            "file1.swift",
            "file2.Swift",
            "file3.SWIFT",
            "file4.swiFT",
            "file5.txt" // Different extension
        ]
        
        for fileName in files {
            let filePath = absoluteTestDir.appending(fileName)
            try fileSystem.writeFileContents(filePath, string: "// \(fileName)")
        }
        
        // Test case-insensitive matching
        let swiftFiles = try getFiles(
            in: testDir,
            matchingExtension: "swift",
            fileSystem: fileSystem
        )
        
        #expect(swiftFiles.count == 4) // All .swift variants, excluding .txt
        
        // Test with uppercase extension
        let swiftFilesUpper = try getFiles(
            in: testDir,
            matchingExtension: "SWIFT",
            fileSystem: fileSystem
        )
        
        #expect(swiftFilesUpper.count == 4) // Should match the same files
        #expect(Set(swiftFiles) == Set(swiftFilesUpper))
    }
    
    // MARK: - Parameterized Tests
    
    @Test("getFiles with case insensitive extensions", arguments: [
        ("swift", ["file1.swift", "file2.Swift", "file3.SWIFT", "file4.swiFT"]),
        ("SWIFT", ["file1.swift", "file2.Swift", "file3.SWIFT", "file4.swiFT"]),
        ("Swift", ["file1.swift", "file2.Swift", "file3.SWIFT", "file4.swiFT"]),
        ("txt", ["file5.txt"])
    ])
    func testCaseInsensitiveExtensionsParameterized(extension: String, expectedFiles: [String]) throws {
        let fileSystem = InMemoryFileSystem()
        let testDir = try AbsolutePath(validating: "/test")
        try fileSystem.createDirectory(testDir, recursive: true)
        
        // Create files with different case extensions
        let allFiles = ["file1.swift", "file2.Swift", "file3.SWIFT", "file4.swiFT", "file5.txt"]
        
        for fileName in allFiles {
            let filePath = testDir.appending(fileName)
            try fileSystem.writeFileContents(filePath, string: "// \(fileName)")
        }
        
        let results = try getFiles(
            in: testDir,
            matchingExtension: `extension`,
            fileSystem: fileSystem
        )
        
        #expect(results.count == expectedFiles.count, "Expected \(expectedFiles.count) files for extension '\(`extension`)'")
        
        for expectedFile in expectedFiles {
            let expectedPath = testDir.appending(expectedFile)
            #expect(results.contains(expectedPath), "Should contain \(expectedFile)")
        }
    }
    
    @Test("getFiles error handling", arguments: [
        ("non-existent directory", "/nonexistent", false),
        ("file instead of directory", "/test.swift", true)
    ])
    func testErrorHandlingParameterized(description: String, path: String, createFile: Bool) throws {
        let fileSystem = InMemoryFileSystem()
        
        if createFile {
            // Create a file for the "file instead of directory" test
            let testFile = try AbsolutePath(validating: path)
            try fileSystem.writeFileContents(testFile, string: "// test file")
        }
        
        let testPath = try AbsolutePath(validating: path)
        
        #expect(throws: StringError.self) {
            try getFiles(
                in: testPath,
                matchingExtension: "swift",
                fileSystem: fileSystem
            )
        }
    }
    
    @Test("getFiles with RelativePath error conditions", arguments: [
        ("invalid path", true, false),
        ("file instead of directory", true, true),
        ("no current working directory", false, false)
    ])
    func testRelativePathErrorConditionsParameterized(description: String, setCwd: Bool, createFile: Bool) throws {
        let fileSystem = InMemoryFileSystem()
        
        if setCwd {
            let cwd = try AbsolutePath(validating: "/current")
            try fileSystem.createDirectory(cwd, recursive: true)
            try fileSystem.changeCurrentWorkingDirectory(to: cwd)
            
            if createFile {
                // Create a file for the "file instead of directory" test
                let testFile = cwd.appending("test.swift")
                try fileSystem.writeFileContents(testFile, string: "// test file")
            }
        }
        
        let testPath = try RelativePath(validating: createFile ? "test.swift" : "nonexistent")
        
        #expect(throws: StringError.self) {
            try getFiles(
                in: testPath,
                matchingExtension: "swift",
                fileSystem: fileSystem
            )
        }
    }
    
    @Test("getFiles with different recursion modes", arguments: [
        (true, 3, "recursive search should find all files"),
        (false, 1, "non-recursive search should find only top-level files")
    ])
    func testRecursionModesParameterized(recursive: Bool, expectedCount: Int, description: String) throws {
        let fileSystem = InMemoryFileSystem()
        let testDir = try AbsolutePath(validating: "/test")
        try fileSystem.createDirectory(testDir, recursive: true)
        
        // Create files at different levels
        let swiftFile1 = testDir.appending("file1.swift")
        let swiftFile2 = testDir.appending("subdir").appending("file2.swift")
        let swiftFile3 = testDir.appending("subdir").appending("nested").appending("file3.swift")
        
        try fileSystem.createDirectory(swiftFile2.parentDirectory, recursive: true)
        try fileSystem.createDirectory(swiftFile3.parentDirectory, recursive: true)
        
        try fileSystem.writeFileContents(swiftFile1, string: "// Swift file 1")
        try fileSystem.writeFileContents(swiftFile2, string: "// Swift file 2")
        try fileSystem.writeFileContents(swiftFile3, string: "// Swift file 3")
        
        let results = try getFiles(
            in: testDir,
            matchingExtension: "swift",
            recursive: recursive,
            fileSystem: fileSystem
        )
        
        #expect(results.count == expectedCount, "\(description): expected \(expectedCount), got \(results.count)")
        
        // Always should contain the top-level file
        #expect(results.contains(swiftFile1), "Should always contain top-level file")
        
        if recursive {
            // Should contain nested files
            #expect(results.contains(swiftFile2), "Recursive search should contain nested files")
            #expect(results.contains(swiftFile3), "Recursive search should contain deeply nested files")
        } else {
            // Should not contain nested files
            #expect(!results.contains(swiftFile2), "Non-recursive search should not contain nested files")
            #expect(!results.contains(swiftFile3), "Non-recursive search should not contain deeply nested files")
        }
    }
    
    @Test("getFiles with RelativePath recursion modes", arguments: [
        (true, 2, "recursive RelativePath search"),
        (false, 1, "non-recursive RelativePath search")
    ])
    func testRelativePathRecursionParameterized(recursive: Bool, expectedCount: Int, description: String) throws {
        let fileSystem = InMemoryFileSystem()
        
        // Set up current working directory
        let cwd = try AbsolutePath(validating: "/current")
        try fileSystem.createDirectory(cwd, recursive: true)
        try fileSystem.changeCurrentWorkingDirectory(to: cwd)
        
        // Create test directory structure
        let testDir = try RelativePath(validating: "test")
        let absoluteTestDir = cwd.appending(testDir)
        try fileSystem.createDirectory(absoluteTestDir, recursive: true)
        
        // Create files at different levels
        let swiftFile1 = absoluteTestDir.appending("file1.swift")
        let swiftFile2 = absoluteTestDir.appending("subdir").appending("file2.swift")
        
        try fileSystem.createDirectory(swiftFile2.parentDirectory, recursive: true)
        try fileSystem.writeFileContents(swiftFile1, string: "// Swift file 1")
        try fileSystem.writeFileContents(swiftFile2, string: "// Swift file 2")
        
        let results = try getFiles(
            in: testDir,
            matchingExtension: "swift",
            recursive: recursive,
            fileSystem: fileSystem
        )
        
        #expect(results.count == expectedCount, "\(description): expected \(expectedCount), got \(results.count)")
        
        let expectedFile1 = swiftFile1.relative(to: cwd)
        #expect(results.contains(expectedFile1), "Should contain top-level file")
        
        let expectedFile2 = swiftFile2.relative(to: cwd)
        if recursive {
            #expect(results.contains(expectedFile2), "Recursive search should contain nested file")
        } else {
            #expect(!results.contains(expectedFile2), "Non-recursive search should not contain nested file")
        }
    }
}