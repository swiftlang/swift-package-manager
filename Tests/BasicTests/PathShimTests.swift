/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import XCTest

import Basic
import POSIX

class PathShimTests : XCTestCase {

    func testResolvingSymlinks() {
        // Make sure the root path resolves to itself.
        XCTAssertEqual(resolveSymlinks(AbsolutePath.root), AbsolutePath.root)
        
        // For the rest of the tests we'll need a temporary directory.
        let tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        // FIXME: it would be better to not need to resolve symbolic links, but we end up relying on /tmp -> /private/tmp.
        let tmpDirPath = resolveSymlinks(tmpDir.path)

        // Create a symbolic link and directory.
        let slnkPath = tmpDirPath.appending(component: "slnk")
        let fldrPath = tmpDirPath.appending(component: "fldr")
        
        // Create a symbolic link pointing at the (so far non-existent) directory.
        try! createSymlink(slnkPath, pointingAt: fldrPath, relative: true)
        
        // Resolving the symlink should not yet change anything.
        XCTAssertEqual(resolveSymlinks(slnkPath), slnkPath)
        
        // Create a directory to be the referent of the symbolic link.
        try! makeDirectories(fldrPath)
        
        // Resolving the symlink should now point at the directory.
        XCTAssertEqual(resolveSymlinks(slnkPath), fldrPath)
        
        // Resolving the directory should still not change anything.
        XCTAssertEqual(resolveSymlinks(fldrPath), fldrPath)
    }

    func testRescursiveDirectoryCreation() {
        // For the tests we'll need a temporary directory.
        let tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        
        // Create a directory under several ancestor directories.
        let dirPath = tmpDir.path.appending(components: "abc", "def", "ghi", "mno", "pqr")
        try! makeDirectories(dirPath)
        
        // Check that we were able to actually create the directory.
        XCTAssertTrue(isDirectory(dirPath))
        
        // Check that there's no error if we try to create the directory again.
        try! makeDirectories(dirPath)
    }
    
    func testRecursiveDirectoryRemoval() {
        // For the tests we'll need a temporary directory.
        let tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        // FIXME: it would be better to not need to resolve symbolic links, but we end up relying on /tmp -> /private/tmp.
        let tmpDirPath = resolveSymlinks(tmpDir.path)

        // Create a couple of directories.  The first one shouldn't end up getting removed, the second one will.
        let keepDirPath = tmpDirPath.appending(components: "abc1")
        try! makeDirectories(keepDirPath)
        let tossDirPath = tmpDirPath.appending(components: "abc2", "def", "ghi", "mno", "pqr")
        try! makeDirectories(tossDirPath)
        
        // Create a symbolic link in a directory to be removed; it points to a directory to not remove.
        let slnkPath = tossDirPath.appending(components: "slnk")
        try! createSymlink(slnkPath, pointingAt: keepDirPath, relative: true)
        
        // Make sure the symbolic link got set up correctly.
        XCTAssertTrue(isSymlink(slnkPath))
        XCTAssertEqual(resolveSymlinks(slnkPath), keepDirPath)
        XCTAssertTrue(isDirectory(resolveSymlinks(slnkPath)))
        
        // Now remove the directory hierarchy that contains the symlink.
        try! removeFileTree(tossDirPath)
        
        // Make sure it got removed, along with the symlink, but that the target of the symlink remains.
        XCTAssertFalse(exists(tossDirPath))
        XCTAssertFalse(isDirectory(tossDirPath))
        XCTAssertTrue(exists(keepDirPath))
        XCTAssertTrue(isDirectory(keepDirPath))
    }
    
    func testCurrentWorkingDirectory() {
        // Test against what POSIX returns, at least for now.
        let cwd = currentWorkingDirectory;
        XCTAssertEqual(cwd, AbsolutePath(getcwd()))
    }
    
    static var allTests = [
        ("testResolvingSymlinks",            testResolvingSymlinks),
        ("testRescursiveDirectoryCreation",  testRescursiveDirectoryCreation),
        ("testRecursiveDirectoryRemoval",    testRecursiveDirectoryRemoval),
        ("testCurrentWorkingDirectory",      testCurrentWorkingDirectory)
    ]
}

class WalkTests : XCTestCase {

    func testNonRecursive() {
        var expected = [
            AbsolutePath("/usr"),
            AbsolutePath("/bin"),
            AbsolutePath("/sbin")
        ]
        for x in try! walk(AbsolutePath("/"), recursively: false) {
            if let i = expected.index(of: x) {
                expected.remove(at: i)
            }
            XCTAssertEqual(2, x.components.count)
        }
        XCTAssertEqual(expected.count, 0)
    }

    func testRecursive() {
        let root = AbsolutePath(#file).parentDirectory.parentDirectory.parentDirectory.appending(component: "Sources")
        var expected = [
            root.appending(component: "Build"),
            root.appending(component: "Utility")
        ]
        for x in try! walk(root) {
            if let i = expected.index(of: x) {
                expected.remove(at: i)
            }
        }
        XCTAssertEqual(expected.count, 0)
    }

    func testSymlinksNotWalked() {
        let tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        // FIXME: it would be better to not need to resolve symbolic links, but we end up relying on /tmp -> /private/tmp.
        let tmpDirPath = resolveSymlinks(tmpDir.path)
            
        try! makeDirectories(tmpDirPath.appending(component: "foo"))
        try! makeDirectories(tmpDirPath.appending(components: "bar", "baz", "goo"))
        try! createSymlink(tmpDirPath.appending(components: "foo", "symlink"), pointingAt: tmpDirPath.appending(component: "bar"), relative: true)

        XCTAssertTrue(isSymlink(tmpDirPath.appending(components: "foo", "symlink")))
        XCTAssertEqual(resolveSymlinks(tmpDirPath.appending(components: "foo", "symlink")), tmpDirPath.appending(component: "bar"))
        XCTAssertTrue(isDirectory(resolveSymlinks(tmpDirPath.appending(components: "foo", "symlink", "baz"))))

        let results = try! walk(tmpDirPath.appending(component: "foo")).map{ $0 }

        XCTAssertEqual(results, [tmpDirPath.appending(components: "foo", "symlink")])
    }

    func testWalkingADirectorySymlinkResolvesOnce() {
        let tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        let tmpDirPath = tmpDir.path
        
        try! makeDirectories(tmpDirPath.appending(components: "foo", "bar"))
        try! makeDirectories(tmpDirPath.appending(components: "abc", "bar"))
        try! createSymlink(tmpDirPath.appending(component: "symlink"), pointingAt: tmpDirPath.appending(component: "foo"), relative: true)
        try! createSymlink(tmpDirPath.appending(components: "foo", "baz"), pointingAt: tmpDirPath.appending(component: "abc"), relative: true)

        XCTAssertTrue(isSymlink(tmpDirPath.appending(component: "symlink")))

        let results = try! walk(tmpDirPath.appending(component: "symlink")).map{ $0 }.sorted()

        // we recurse a symlink to a directory, so this should work,
        // but `abc` should not show because `baz` is a symlink too
        // and that should *not* be followed

        XCTAssertEqual(results, [tmpDirPath.appending(components: "symlink", "bar"), tmpDirPath.appending(components: "symlink", "baz")])
    }

    static var allTests = [
        ("testNonRecursive",                          testNonRecursive),
        ("testRecursive",                             testRecursive),
        ("testSymlinksNotWalked",                     testSymlinksNotWalked),
        ("testWalkingADirectorySymlinkResolvesOnce",  testWalkingADirectorySymlinkResolvesOnce),
    ]
}

class FileAccessTests : XCTestCase {
    
    private func loadInputFile(_ name: String) throws -> FileHandle {
        let input = AbsolutePath(#file).parentDirectory.appending(components: "Inputs", name)
        return try fopen(input, mode: .read)
    }
    
    func testOpenFile() {
        do {
            let file = try loadInputFile("empty_file")
            XCTAssertEqual(try file.readFileContents(), "")
        } catch {
            XCTFail("The file should be opened without problem")
        }
    }
    
    func testOpenFileFail() {
        do {
            let file = try loadInputFile("file_not_existing")
            let _ = try file.readFileContents()
            XCTFail("The file should not be opened since it is not existing")
        } catch {
            
        }
    }
    
    func testReadRegularTextFile() {
        do {
            let file = try loadInputFile("regular_text_file")
            var generator = try file.readFileContents().components(separatedBy: "\n").makeIterator()
            XCTAssertEqual(generator.next(), "Hello world")
            XCTAssertEqual(generator.next(), "It is a regular text file.")
            XCTAssertEqual(generator.next(), "")
            XCTAssertNil(generator.next())
        } catch {
            XCTFail("The file should be opened without problem")
        }
    }
    
    func testReadRegularTextFileWithSeparator() {
        do {
            let file = try loadInputFile("regular_text_file")
            var generator = try file.readFileContents().components(separatedBy: " ").makeIterator()
            XCTAssertEqual(generator.next(), "Hello")
            XCTAssertEqual(generator.next(), "world\nIt")
            XCTAssertEqual(generator.next(), "is")
            XCTAssertEqual(generator.next(), "a")
            XCTAssertEqual(generator.next(), "regular")
            XCTAssertEqual(generator.next(), "text")
            XCTAssertEqual(generator.next(), "file.\n")
            XCTAssertNil(generator.next())
        } catch {
            XCTFail("The file should be opened without problem")
        }
    }
    
    static var allTests = [
        ("testOpenFile",                          testOpenFile),
        ("testOpenFileFail",                      testOpenFileFail),
        ("testReadRegularTextFile",               testReadRegularTextFile),
        ("testReadRegularTextFileWithSeparator",  testReadRegularTextFileWithSeparator),
    ]
}

