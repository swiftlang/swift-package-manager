//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import SourceControl

import struct TSCBasic.StringError
import struct TSCUtility.Version

package enum PackageArchiver {
    package static func archive(
        packageDirectory: AbsolutePath,
        archivePath: AbsolutePath,
        archivePrefix: String,
        workingDirectory: AbsolutePath,
        workingFilesToCopy: [String] = [],
        cancellator: Cancellator?,
        observabilityScope: ObservabilityScope
    ) async throws {
        try localFileSystem.validateNoEscapingSymlinks(in: packageDirectory)

        try localFileSystem.createDirectory(workingDirectory, recursive: true)
        let gitRepositoryProvider = GitRepositoryProvider()
        let isGitRepository = (try? gitRepositoryProvider.isValidDirectory(packageDirectory)) == true

        // If the package directory is a git repository, we can leverage `git archive` to create the archive,
        // which will automatically exclude ignored files and directories based on the users .gitignore and
        // .gitattributes configuration.
        if isGitRepository {
            let repository = GitRepository(path: packageDirectory, cancellator: cancellator)
            guard repository.exists(revision: .init(identifier: "HEAD")) else {
                throw StringError(
                    "Cannot archive git repository at '\(packageDirectory)' because it has no commits. Create an initial commit before archiving."
                )
            }

            if workingFilesToCopy.isEmpty {
                try repository.archive(
                    to: archivePath,
                    prefix: archivePrefix,
                    exportIgnoring: Self.exportIgnorePatterns
                )
                return
            }

            let sourceDirectory = workingDirectory.appending(components: "source", archivePrefix)
            try localFileSystem.createDirectory(sourceDirectory, recursive: true)
            try await Self.populateFromGitHead(
                sourceDirectory: sourceDirectory,
                workingDirectory: workingDirectory,
                cancellator: cancellator,
                repository: repository
            )
            try Self.injectWorkingFiles(
                workingFilesToCopy,
                from: workingDirectory,
                into: sourceDirectory,
                observabilityScope: observabilityScope
            )
            let archiver = UniversalArchiver(localFileSystem, cancellator)
            try await archiver.compress(directory: sourceDirectory, to: archivePath)
            return
        }

        // If the package directory is not a git repository, we fall back to a best-effort approach
        // of copying the files while omitting any that look like sensitive files based on their names.
        observabilityScope.emit(
            warning: "archiving a non-git package directory uses a best-effort filter when omitting sensitive files; consider initializing a git repository or using '.gitattributes export-ignore' for deterministic filtering"
        )
        let sourceDirectory = workingDirectory.appending(components: "source", archivePrefix)
        try localFileSystem.createDirectory(sourceDirectory, recursive: true)
        try Self.copyFilteringSensitiveFiles(
            from: packageDirectory,
            to: sourceDirectory
        )
        try Self.injectWorkingFiles(
            workingFilesToCopy,
            from: workingDirectory,
            into: sourceDirectory,
            observabilityScope: observabilityScope
        )
        let archiver = UniversalArchiver(localFileSystem, cancellator)
        try await archiver.compress(directory: sourceDirectory, to: archivePath)
    }

    @discardableResult
    package static func archive(
        packageIdentity: PackageIdentity,
        packageVersion: Version,
        packageDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        workingFilesToCopy: [String],
        cancellator: Cancellator?,
        observabilityScope: ObservabilityScope
    ) async throws -> AbsolutePath {
        let archivePath = workingDirectory.appending("\(packageIdentity)-\(packageVersion).zip")
        try await Self.archive(
            packageDirectory: packageDirectory,
            archivePath: archivePath,
            archivePrefix: "\(packageIdentity)",
            workingDirectory: workingDirectory,
            workingFilesToCopy: workingFilesToCopy,
            cancellator: cancellator,
            observabilityScope: observabilityScope
        )
        return archivePath
    }

    /// Overwrites files in `sourceDirectory` with replacements staged under `workingDirectory`.
    ///
    /// Used by the publish flow to substitute caller-prepared variants of files that already
    /// exist in the source tree — typically a signed manifest replacing the on-disk `Package.swift`
    /// — after the source tree has been populated from git or a filtered copy.
    ///
    /// - Parameters:
    ///   - workingFilesToCopy: Paths relative to both `workingDirectory` (read from) and
    ///     `sourceDirectory` (written to). Each path must exist under `workingDirectory`.
    ///   - workingDirectory: The directory holding the replacement files.
    ///   - sourceDirectory: The populated source tree to be modified in place.
    private static func injectWorkingFiles(
        _ workingFilesToCopy: [String],
        from workingDirectory: AbsolutePath,
        into sourceDirectory: AbsolutePath,
        observabilityScope: ObservabilityScope
    ) throws {
        for item in workingFilesToCopy {
            let replacementPath = workingDirectory.appending(item)
            let replacement = try localFileSystem.readFileContents(replacementPath)

            let toBeReplacedPath = sourceDirectory.appending(item)

            observabilityScope.emit(info: "replacing '\(toBeReplacedPath)' with '\(replacementPath)'")
            try localFileSystem.writeFileContents(toBeReplacedPath, bytes: replacement)
        }
    }

    /// Materializes the contents of `HEAD` into `sourceDirectory` with export-ignore filtering applied.
    ///
    /// Produces a tree containing only files that `git archive HEAD` would ship, minus anything
    /// matching `Self.exportIgnorePatterns`. The tree is suitable for further mutation (e.g., by
    /// `injectWorkingFiles`) before being re-compressed into the final archive.
    ///
    /// Implementation: archives `HEAD` to an intermediate zip in `workingDirectory`, extracts it
    /// into `sourceDirectory`, then strips the single top-level prefix directory that
    /// `git archive` adds. The intermediate zip is deleted on success. The extracted tree is
    /// validated for symlinks escaping `sourceDirectory`; a committed escaping symlink that survives
    /// `git archive` will cause this step to throw.
    private static func populateFromGitHead(
        sourceDirectory: AbsolutePath,
        workingDirectory: AbsolutePath,
        cancellator: Cancellator?,
        repository: GitRepository
    ) async throws {
        let intermediateArchive = workingDirectory.appending("git-source.zip")
        if localFileSystem.exists(intermediateArchive) {
            try localFileSystem.removeFileTree(intermediateArchive)
        }

        try repository.archive(
            to: intermediateArchive,
            exportIgnoring: Self.exportIgnorePatterns
        )

        let archiver = UniversalArchiver(localFileSystem, cancellator)
        try await archiver.extract(from: intermediateArchive, to: sourceDirectory)
        try localFileSystem.stripFirstLevel(of: sourceDirectory)
        try localFileSystem.removeFileTree(intermediateArchive)
        try localFileSystem.validateNoEscapingSymlinks(in: sourceDirectory)
    }

    private static var exportIgnorePatterns: [String] {
        var patterns = Ignored.filenames.sorted()
        patterns.append(".env")
        patterns.append(".env.*")
        patterns += Ignored.extensions.sorted().map { "*\($0)" }
        return patterns
    }

    private enum Ignored {
        static let directories: Set<String> = [
            ".build", ".git", ".hg", ".svn", ".swiftpm",
        ]

        static let filenames: Set<String> = [
            ".ds_store",
            ".gitattributes",
            ".gitignore",
            ".netrc",
            ".npmrc",
            "credentials",
            "credentials.json",
            "id_ecdsa",
            "id_ecdsa.pub",
            "id_ed25519",
            "id_ed25519.pub",
            "id_rsa",
            "id_rsa.pub",
            "secrets.json",
        ]

        static let extensions: Set<String> = [
            ".key", ".p12", ".pem", ".pfx",
        ]
    }

    private static func isSensitiveFilename(_ name: String) -> Bool {
        let lower = name.lowercased()
        if Ignored.filenames.contains(lower) { return true }
        if lower == ".env" || lower.hasPrefix(".env.") { return true }
        return Ignored.extensions.contains { lower.hasSuffix($0) }
    }

    private static func copyFilteringSensitiveFiles(
        from source: AbsolutePath,
        to destination: AbsolutePath
    ) throws {
        let entries = try localFileSystem.getDirectoryContents(source)
        for entry in entries {
            let sourceEntry = source.appending(component: entry)
            let destinationEntry = destination.appending(component: entry)

            if localFileSystem.isDirectory(sourceEntry) && !localFileSystem.isSymlink(sourceEntry) {
                if Ignored.directories.contains(entry.lowercased()) { continue }
                try localFileSystem.createDirectory(destinationEntry, recursive: false)
                try Self.copyFilteringSensitiveFiles(from: sourceEntry, to: destinationEntry)
            } else {
                if Self.isSensitiveFilename(entry) { continue }
                try localFileSystem.copy(from: sourceEntry, to: destinationEntry)
            }
        }
    }
}
