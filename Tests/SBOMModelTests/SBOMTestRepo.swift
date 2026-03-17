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

import _InternalTestSupport
import Basics
import Foundation
import SourceControl
import class TSCBasic.Process
import enum TSCUtility.Git

enum SBOMTestRepo {
    static func setupSPMTestRepo() throws -> (GitRepository, AbsolutePath) {
        let uniqueID = UUID().uuidString
        let path = AbsolutePath("/tmp/SwiftPM-mock-\(uniqueID)")

        try localFileSystem.createDirectory(path, recursive: true)
        
        let repo = GitRepository(path: path)
        try repo.create()
        
        try Process.checkNonZeroExit(
            args: Git.tool,
            "-C",
            path.pathString,
            "remote",
            "add",
            "test_origin",
            SBOMTestStore.swiftPMURL
        )
        
        let file = path.appending("Package.swift")
        try localFileSystem.writeFileContents(file, string: "// swift-tools-version: 5.9\nimport PackageDescription\n")
        try repo.stageEverything()
        try repo.commit(message: "Initial commit")
        guard let branch = try repo.getCurrentBranch() else {
            throw SBOMTestError.failedToGetCurrentBranch
        }
        
        try Process.checkNonZeroExit(
            args: Git.tool,
            "-C",
            path.pathString,
            "config",
            "branch.\(branch).remote",
            "test_origin"
        )

        return (repo, path)
    }

    static func setupSwiftlyTestRepo() throws -> (GitRepository, AbsolutePath) {
        let uniqueID = UUID().uuidString
        let path = AbsolutePath("/tmp/swiftly-mock-\(uniqueID)")

        try localFileSystem.createDirectory(path, recursive: true)
        
        let repo = GitRepository(path: path)
        try repo.create()
        
        try Process.checkNonZeroExit(
            args: Git.tool,
            "-C",
            path.pathString,
            "remote",
            "add",
            "test_origin",
            SBOMTestStore.swiftlyURL
        )
        
        let file = path.appending("Package.swift")
        try localFileSystem.writeFileContents(file, string: "// swift-tools-version: 5.9\nimport PackageDescription\n")
        try repo.stageEverything()
        try repo.commit(message: "Initial commit")
        guard let branch = try repo.getCurrentBranch() else {
            throw SBOMTestError.failedToGetCurrentBranch
        }
        
        try repo.tag(name: "v1.0.0")
        
        try Process.checkNonZeroExit(
            args: Git.tool,
            "-C",
            path.pathString,
            "config",
            "branch.\(branch).remote",
            "test_origin"
        )

        return (repo, path)
    }

    /// Clean up a test repository directory
    static func cleanup(_ path: AbsolutePath) throws {
        if localFileSystem.exists(path) {
            try localFileSystem.removeFileTree(path)
        }
    }
}
