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
        
        // Create a symbolic link and directory.
        let slnkPath = tmpDir.path.appending("slnk")
        let fldrPath = tmpDir.path.appending("fldr")
        
        // Create a symbolic link pointing at the (so far non-existent) directory.
        try! symlink(create: slnkPath.asString, pointingAt: fldrPath.asString, relativeTo: tmpDir.path.asString)
        
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
    
    static var allTests = [
        ("testResolvingSymlinks",  testResolvingSymlinks),
        ("testRescursiveDirectoryCreation",  testRescursiveDirectoryCreation)
    ]
}
