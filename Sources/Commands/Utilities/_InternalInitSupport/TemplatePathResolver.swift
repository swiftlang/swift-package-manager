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

import Workspace
import Basics
import PackageModel
import TSCBasic
import SourceControl
import Foundation
import TSCUtility


struct TemplatePathResolver {
    let templateType: InitTemplatePackage.TemplateType?
    let templateDirectory: Basics.AbsolutePath?
    let templateURL: String?
    let requirement: PackageDependency.SourceControl.Requirement?

    func resolve() async throws -> Basics.AbsolutePath {
        switch templateType {
        case .local:
            guard let path = templateDirectory else {
                throw StringError("Template path must be specified for local templates.")
            }
            return path

        case .git:
            guard let url = templateURL else {
                throw StringError("Missing Git URL for git template.")
            }

            guard let gitRequirement = requirement else {
                throw StringError("Missing version requirement for git template.")
            }

            return try await GitTemplateFetcher(destination: url, requirement: gitRequirement).fetch()

        case .registry:
            throw StringError("Registry templates not supported yet.")

        case .none:
            throw StringError("Missing --template-type.")
        }
    }

    struct GitTemplateFetcher {
        let destination: String
        let requirement: PackageDependency.SourceControl.Requirement

        func fetch() async throws -> Basics.AbsolutePath {

            let fetchStandalonePackageByURL = { () async throws -> Basics.AbsolutePath in
                try withTemporaryDirectory(removeTreeOnDeinit: false) { (tempDir: Basics.AbsolutePath) in

                    let url = SourceControlURL(destination)
                    let repositorySpecifier = RepositorySpecifier(url: url)
                    let repositoryProvider = GitRepositoryProvider()

                    
                    let bareCopyPath = tempDir.appending(component: "bare-copy")

                    let workingCopyPath = tempDir.appending(component: "working-copy")

                    try fetchBareRepository(provider: repositoryProvider, specifier: repositorySpecifier, to: bareCopyPath)
                    try validateDirectory(provider: repositoryProvider, at: bareCopyPath)


                    try FileManager.default.createDirectory(
                        atPath: workingCopyPath.pathString,
                        withIntermediateDirectories: true
                    )

                    let repository = try repositoryProvider.createWorkingCopyFromBare(
                        repository: repositorySpecifier,
                        sourcePath: bareCopyPath,
                        at: workingCopyPath,
                        editable: true
                    )

                    try FileManager.default.removeItem(at: bareCopyPath.asURL)

                    try checkout(repository: repository)

                    return workingCopyPath
                }
            }

            return try await fetchStandalonePackageByURL()
        }

        private func fetchBareRepository(
            provider: GitRepositoryProvider,
            specifier: RepositorySpecifier,
            to path: Basics.AbsolutePath
        ) throws {
            try provider.fetch(repository: specifier, to: path)
        }

        private func validateDirectory(provider: GitRepositoryProvider, at path: Basics.AbsolutePath) throws {
            guard try provider.isValidDirectory(path) else {
                throw InternalError("Invalid directory at \(path)")
            }
        }

        private func checkout(repository: WorkingCheckout) throws {
            switch requirement {
            case .exact(let version):
                try repository.checkout(tag: version.description)

            case .branch(let name):
                try repository.checkout(branch: name)

            case .revision(let revision):
                try repository.checkout(revision: .init(identifier: revision))

            case .range(let range):
                let tags = try repository.getTags()
                let versions = tags.compactMap { Version($0) }
                let filteredVersions = versions.filter { range.contains($0) }
                guard let latestVersion = filteredVersions.max() else {
                    throw InternalError("No tags found within the specified version range \(range)")
                }
                try repository.checkout(tag: latestVersion.description)
            }
        }

    }
}
