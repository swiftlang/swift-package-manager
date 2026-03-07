//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import Foundation
import SourceControl

import struct TSCBasic.ByteString

// FIXME: Use Synchronization.Mutex when available in SwiftPM's supported deployment targets.
private final class Mutex<Value>: @unchecked Sendable {
    var lock: NSLock
    var value: Value

    init(value: Value) {
        self.lock = .init()
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        self.lock.lock()
        defer { self.lock.unlock() }
        return body(&self.value)
    }
}

/// Caches repository identity and git context used by manifest loading.
package final class ManifestGitInformationCache: @unchecked Sendable {
    private enum ScopeKey: Hashable {
        case repository(AbsolutePath)
        case directory(AbsolutePath)
    }

    private enum RepositoryKey: Equatable {
        case repository(AbsolutePath)
        case notRepository
    }

    private enum CachedGitInformation {
        case value(ContextModel.GitInformation?)

        var gitInformation: ContextModel.GitInformation? {
            switch self {
            case .value(let gitInformation):
                gitInformation
            }
        }
    }

    private enum LookupAction {
        case returnValue(ContextModel.GitInformation?)
        case wait(InFlight)
        case load(InFlight, epoch: UInt64)
    }

    private final class InFlight: @unchecked Sendable {
        private let group = DispatchGroup()

        init() {
            self.group.enter()
        }

        func wait() {
            self.group.wait()
        }

        func finish() {
            self.group.leave()
        }
    }

    private struct State {
        var epoch: UInt64 = 0
        var repositoryKeyCache: [AbsolutePath: RepositoryKey] = [:]
        var gitInformationByRepository: [AbsolutePath: CachedGitInformation] = [:]
        var gitInformationByDirectory: [AbsolutePath: CachedGitInformation] = [:]
        var inFlightByScope: [ScopeKey: InFlight] = [:]

        mutating func storeRepositoryKey(_ key: RepositoryKey, for paths: [AbsolutePath]) {
            for path in paths {
                self.repositoryKeyCache[path] = key
            }
        }
    }

    private let state = Mutex(value: State())

    package init() {}

    func clear() {
        self.state.withLock { state in
            let nextEpoch = state.epoch &+ 1
            state = .init()
            state.epoch = nextEpoch
        }
    }

    func gitInformation(for directory: AbsolutePath) -> ContextModel.GitInformation? {
        while true {
            let repositoryKey = self.repositoryKey(for: directory)
            let scopeKey = Self.scopeKey(for: directory, repositoryKey: repositoryKey)

            switch self.lookupAction(for: directory, repositoryKey: repositoryKey, scopeKey: scopeKey) {
            case .returnValue(let gitInformation):
                return gitInformation
            case .wait(let inFlight):
                inFlight.wait()
            case .load(let inFlight, let epoch):
                defer { inFlight.finish() }

                let gitInformation = Self.loadGitInformation(for: directory)
                let cachedGitInformation = CachedGitInformation.value(gitInformation)

                self.state.withLock { state in
                    if state.epoch == epoch {
                        state.gitInformationByDirectory[directory] = cachedGitInformation
                        if case .repository(let gitDirectory) = repositoryKey {
                            state.gitInformationByRepository[gitDirectory] = cachedGitInformation
                        }
                    }

                    if let currentInFlight = state.inFlightByScope[scopeKey],
                       currentInFlight === inFlight
                    {
                        state.inFlightByScope.removeValue(forKey: scopeKey)
                    }
                }

                return gitInformation
            }
        }
    }

    private func repositoryKey(for directory: AbsolutePath) -> RepositoryKey {
        self.state.withLock { state in
            if let cached = state.repositoryKeyCache[directory] {
                return cached
            }

            var visitedPaths = [AbsolutePath]()
            var currentPath = directory
            while true {
                if let cached = state.repositoryKeyCache[currentPath] {
                    state.storeRepositoryKey(cached, for: visitedPaths)
                    return cached
                }

                visitedPaths.append(currentPath)

                if let repositoryPath = Self.repositoryPathIfAny(for: currentPath) {
                    let normalizedRepositoryPath = (try? resolveSymlinks(repositoryPath)) ?? repositoryPath
                    let key: RepositoryKey = .repository(normalizedRepositoryPath)
                    state.storeRepositoryKey(key, for: visitedPaths)
                    return key
                }

                if currentPath.isRoot {
                    break
                }
                currentPath = currentPath.parentDirectory
            }

            state.storeRepositoryKey(.notRepository, for: visitedPaths)
            return .notRepository
        }
    }

    private func lookupAction(
        for directory: AbsolutePath,
        repositoryKey: RepositoryKey,
        scopeKey: ScopeKey
    ) -> LookupAction {
        self.state.withLock { state in
            if let cached = state.gitInformationByDirectory[directory] {
                return .returnValue(cached.gitInformation)
            }

            if case .repository(let gitDirectory) = repositoryKey,
               let cached = state.gitInformationByRepository[gitDirectory]
            {
                state.gitInformationByDirectory[directory] = cached
                return .returnValue(cached.gitInformation)
            }

            if let inFlight = state.inFlightByScope[scopeKey] {
                return .wait(inFlight)
            }

            let inFlight = InFlight()
            state.inFlightByScope[scopeKey] = inFlight
            return .load(inFlight, epoch: state.epoch)
        }
    }

    private static func scopeKey(for directory: AbsolutePath, repositoryKey: RepositoryKey) -> ScopeKey {
        switch repositoryKey {
        case .repository(let gitDirectory):
            .repository(gitDirectory)
        case .notRepository:
            .directory(directory)
        }
    }

    // Git worktrees use a `.git` file containing `gitdir: <path>` instead of a `.git` directory.
    private static func repositoryPathIfAny(for directory: AbsolutePath) -> AbsolutePath? {
        let gitPath = directory.appending(component: ".git")
        if localFileSystem.isDirectory(gitPath) {
            return gitPath
        }

        guard localFileSystem.isFile(gitPath),
              let gitPathContents = try? localFileSystem.readFileContents(gitPath)
        else {
            return nil
        }

        let contentString = String(decoding: gitPathContents.contents, as: UTF8.self)
        guard let firstLine = contentString.split(whereSeparator: \.isNewline).first else {
            return nil
        }

        let expectedPrefix = "gitdir:"
        let firstLineString = String(firstLine)
        guard firstLineString.lowercased().hasPrefix(expectedPrefix) else {
            return nil
        }

        let gitDirectoryString = firstLineString
            .dropFirst(expectedPrefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gitDirectoryString.isEmpty else {
            return nil
        }

        return try? AbsolutePath(validating: gitDirectoryString, relativeTo: directory)
    }

    private static func loadGitInformation(for directory: AbsolutePath) -> ContextModel.GitInformation? {
        do {
            let repo = GitRepository(path: directory)
            return try ContextModel.GitInformation(
                currentTag: repo.getCurrentTag(),
                currentCommit: repo.getCurrentRevision().identifier,
                hasUncommittedChanges: repo.hasUncommittedChanges()
            )
        } catch {
            return nil
        }
    }
}
