/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import Basic
import POSIX
import Utility

class PathShimTests : XCTestCase {

    func testResolvingSymlinks() {
        // Make sure the root path resolves to itself.
        XCTAssertEqual(resolveSymlinks(AbsolutePath.root), AbsolutePath.root)
        
        // For the rest of the tests we'll need a temporary directory.
        let tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        // FIXME: it would be better to not need to resolve symbolic links, but we end up relying on /tmp -> /private/tmp.
        let tmpDirPath = resolveSymlinks(tmpDir.path)

        // Create a symbolic link and directory.
        let slnkPath = tmpDirPath.appending("slnk")
        let fldrPath = tmpDirPath.appending("fldr")
        
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
        XCTAssertTrue(dirPath.asString.isDirectory)
        
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
        XCTAssertTrue(slnkPath.asString.isSymlink)
        XCTAssertEqual(resolveSymlinks(slnkPath), keepDirPath)
        XCTAssertTrue(resolveSymlinks(slnkPath).asString.isDirectory)
        
        // Now remove the directory hierarchy that contains the symlink.
        try! removeFileTree(tossDirPath)
        
        // Make sure it got removed, along with the symlink, but that the target of the symlink remains.
        XCTAssertFalse(tossDirPath.asString.exists)
        XCTAssertFalse(tossDirPath.asString.isDirectory)
        XCTAssertTrue(keepDirPath.asString.exists)
        XCTAssertTrue(keepDirPath.asString.isDirectory)
    }
    
    static var allTests = [
        ("testResolvingSymlinks",            testResolvingSymlinks),
        ("testRescursiveDirectoryCreation",  testRescursiveDirectoryCreation),
        ("testRecursiveDirectoryRemoval",    testRecursiveDirectoryRemoval)
    ]
}

class WalkTests : XCTestCase {

    func testNonRecursive() {
        var expected = [
            AbsolutePath("/usr"),
            AbsolutePath("/bin"),
            AbsolutePath("/sbin")
        ]
        for x in try! walk("/", recursively: false) {
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
            
        try! makeDirectories(tmpDirPath.appending("foo"))
        try! makeDirectories(tmpDirPath.appending("bar/baz/goo"))
        try! createSymlink(tmpDirPath.appending("foo/symlink"), pointingAt: tmpDirPath.appending("bar"), relative: true)

        XCTAssertTrue(tmpDirPath.appending("foo/symlink").asString.isSymlink)
        XCTAssertEqual(resolveSymlinks(tmpDirPath.appending("foo/symlink")), tmpDirPath.appending("bar"))
        XCTAssertTrue(resolveSymlinks(tmpDirPath.appending("foo/symlink/baz")).asString.isDirectory)

        let results = try! walk(tmpDirPath.appending("foo")).map{ $0 }

        XCTAssertEqual(results, [tmpDirPath.appending("foo/symlink")])
    }

    func testWalkingADirectorySymlinkResolvesOnce() {
        let tmpDir = try! TemporaryDirectory(removeTreeOnDeinit: true)
        let tmpDirPath = tmpDir.path
        
        try! makeDirectories(tmpDirPath.appending("foo/bar"))
        try! makeDirectories(tmpDirPath.appending("abc/bar"))
        try! createSymlink(tmpDirPath.appending("symlink"), pointingAt: tmpDirPath.appending("foo"), relative: true)
        try! createSymlink(tmpDirPath.appending("foo/baz"), pointingAt: tmpDirPath.appending("abc"), relative: true)

        XCTAssertTrue(tmpDirPath.appending("symlink").asString.isSymlink)

        let results = try! walk(tmpDirPath.appending("symlink")).map{ $0 }.sorted()

        // we recurse a symlink to a directory, so this should work,
        // but `abc` should not show because `baz` is a symlink too
        // and that should *not* be followed

        XCTAssertEqual(results, [tmpDirPath.appending("symlink/bar"), tmpDirPath.appending("symlink/baz")])
    }

    static var allTests = [
        ("testNonRecursive",                          testNonRecursive),
        ("testRecursive",                             testRecursive),
        ("testSymlinksNotWalked",                     testSymlinksNotWalked),
        ("testWalkingADirectorySymlinkResolvesOnce",  testWalkingADirectorySymlinkResolvesOnce),
    ]
}

