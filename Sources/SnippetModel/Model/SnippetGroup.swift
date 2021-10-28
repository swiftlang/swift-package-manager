/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageGraph
import TSCBasic

public struct SnippetGroup {
    public var name: String
    public var baseDirectory: AbsolutePath
    public var snippets: [Snippet]
    public var explanation: String

    public init(name: String, baseDirectory: AbsolutePath, snippets: [Snippet], explanation: String) {
        self.name = name
        self.baseDirectory = baseDirectory
        self.snippets = snippets
        self.explanation = explanation
        for index in self.snippets.indices {
            self.snippets[index].groupName = baseDirectory.basename
        }
    }
}

fileprivate func files(in directory: AbsolutePath, fileExtension: String? = nil) throws -> [AbsolutePath] {
    guard localFileSystem.isDirectory(directory) else {
        return []
    }

    let files = try localFileSystem.getDirectoryContents(directory)
        .map { directory.appending(RelativePath($0)) }
        .filter { localFileSystem.isFile($0) }

    guard let fileExtension = fileExtension else {
        return files
    }

    return files.filter { $0.extension == fileExtension }
}

fileprivate func subdirectories(in directory: AbsolutePath) throws -> [AbsolutePath] {
    guard localFileSystem.isDirectory(directory) else {
        return []
    }
    return try localFileSystem.getDirectoryContents(directory)
        .map { directory.appending(RelativePath($0)) }
        .filter { localFileSystem.isDirectory($0) }
}

extension Array where Element == SnippetGroup {
    public init(fromPackage package: ResolvedPackage) throws {
        let snippetsDirectory = package.path.appending(component: "Snippets")
        guard localFileSystem.isDirectory(snippetsDirectory) else {
            self = []
            return
        }

        let topLevelSnippets = try files(in: snippetsDirectory, fileExtension: "swift")
            .map { try Snippet(parsing: $0) }

        let topLevelSnippetGroup = SnippetGroup(name: "Getting Started",
                                                baseDirectory: snippetsDirectory,
                                                snippets: topLevelSnippets,
                                                explanation: "")

        let subdirectoryGroups = try subdirectories(in: snippetsDirectory)
            .map { subdirectory -> SnippetGroup in
                let snippets = try files(in: subdirectory, fileExtension: "swift")
                    .map { try Snippet(parsing: $0) }

                let explanationFile = subdirectory.appending(component: "Explanation.md")

                let snippetGroupExplanation: String
                if localFileSystem.isFile(explanationFile) {
                    snippetGroupExplanation = try String(contentsOf: explanationFile.asURL)
                } else {
                    snippetGroupExplanation = ""
                }

                return SnippetGroup(name: subdirectory.basename,
                                    baseDirectory: subdirectory,
                                    snippets: snippets,
                                    explanation: snippetGroupExplanation)
            }

        let snippetGroups = [topLevelSnippetGroup] + subdirectoryGroups.sorted {
            $0.baseDirectory.basename < $1.baseDirectory.basename
        }

        self = snippetGroups.filter { !$0.snippets.isEmpty }
    }
}
