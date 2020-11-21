/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCUtility
import TSCBasic
import SourceControl
import PackageLoading
import PackageModel
import Workspace
import Foundation

/// An editor for Swift packages.
///
/// This class provides high-level functionality for performing
/// editing operations a package.
public final class PackageEditor {

    /// Reference to the package editor context.
    let context: PackageEditorContext

    /// Create a package editor instance.
    public convenience init(manifestPath: AbsolutePath,
                            repositoryManager: RepositoryManager,
                            toolchain: UserToolchain) throws {
        self.init(context: try PackageEditorContext(manifestPath: manifestPath,
                                                    repositoryManager: repositoryManager,
                                                    toolchain: toolchain))
    }

    /// Create a package editor instance.
    public init(context: PackageEditorContext) {
        self.context = context
    }

    /// The file system to perform disk operations on.
    var fs: FileSystem {
        return context.fs
    }

    /// Add a package dependency.
    public func addPackageDependency(url: String, requirement: PackageDependencyRequirement?) throws {
      var requirement = requirement
        let manifestPath = context.manifestPath
        // Validate that the package doesn't already contain this dependency.
        let loadedManifest = try context.loadManifest(at: context.manifestPath.parentDirectory)
        let containsDependency = loadedManifest.dependencies.contains {
            return PackageIdentity(url: url) == PackageIdentity(url: $0.url)
        }
        guard !containsDependency else {
            throw StringError("'\(url)' is already a package dependency")
        }

        // If the input URL is a path, force the requirement to be a local package.
        if TSCUtility.URL.scheme(url) == nil {
            guard requirement == nil || requirement == .localPackage else {
                throw StringError("'\(url)' is a local path, but a non-local requirement was specified")
            }
            requirement = .localPackage
        }

        // Load the dependency manifest depending on the inputs.
        let dependencyManifest: Manifest
        if requirement == .localPackage {
            let path = AbsolutePath(url, relativeTo: fs.currentWorkingDirectory!)
            dependencyManifest = try context.loadManifest(at: path)
            requirement = .localPackage
        } else {
            // Otherwise, first lookup the dependency.
            let spec = RepositorySpecifier(url: options.url)
            let handle = try temp_await{ context.repositoryManager.lookup(repository: spec, completion: $0) }
            let repo = try handle.open()

            // Compute the requirement.
            if let inputRequirement = requirement {
                requirement = inputRequirement
            } else {
                // Use the latest version or the master branch.
                let versions = repo.tags.compactMap{ Version(string: $0) }
                let latestVersion = versions.filter({ $0.prereleaseIdentifiers.isEmpty }).max() ?? versions.max()
                // FIXME: Also look for main, see if it exists.
                requirement = latestVersion.map{ PackageDependencyRequirement.upToNextMajor($0.description) } ?? PackageDependencyRequirement.branch("master")
            }

            // Load the manifest.
            let revision = try repo.resolveRevision(identifier: requirement!.ref!)
            let repoFS = try repo.openFileView(revision: revision)
            dependencyManifest = try context.loadManifest(at: .root, fs: repoFS)
        }

        // Add the package dependency.
        let manifestContents = try fs.readFileContents(manifestPath).cString
        let editor = try ManifestRewriter(manifestContents)
        try editor.addPackageDependency(name: dependencyManifest.name, url: url, requirement: requirement!)

        // FIXME: should this be opt-in?
        // Add the product in the first regular target, if possible.
        let productName = dependencyManifest.products.filter{ $0.type.isLibrary }.map{ $0.name }.first
        let destTarget = loadedManifest.targets.filter{ $0.type == .regular }.first
        if let product = productName,
            let destTarget = destTarget,
            !destTarget.dependencies.containsDependency(product) {
            try editor.addTargetDependency(target: destTarget.name, dependency: product)
        }

        // FIXME: We should verify our edits by loading the edited manifest before writing it to disk.
        try fs.writeFileContents(manifestPath, bytes: ByteString(encodingAsUTF8: editor.editedManifest))
    }

    /// Add a new target.
    public func addTarget(name targetName: String, type targetType: TargetType?) throws {
        let manifestPath = context.manifestPath
        let testTargetName = targetName + "Tests"

        // Validate that the package doesn't already contain a target with the same name.
        let loadedManifest = try context.loadManifest(at: manifestPath.parentDirectory)
        if loadedManifest.targets.contains(where: { $0.name == targetName }) {
            throw StringError("a target named '\(targetName)' already exists")
        }

        let manifestContents = try fs.readFileContents(manifestPath).cString
        let editor = try ManifestRewriter(manifestContents)
        // FIXME: Account for the targetType parameter
        try editor.addTarget(targetName: targetName)
        try editor.addTarget(targetName: testTargetName, type: .test)
        try editor.addTargetDependency(target: testTargetName, dependency: targetName)

        // FIXME: We should verify our edits by loading the edited manifest before writing it to disk.
        try fs.writeFileContents(manifestPath, bytes: ByteString(encodingAsUTF8: editor.editedManifest))

        // Write template files.
        let targetPath = manifestPath.parentDirectory.appending(components: "Sources", targetName)
        if !localFileSystem.exists(targetPath) {
            let file = targetPath.appending(components: targetName + ".swift")
            try fs.createDirectory(targetPath)
            try fs.writeFileContents(file, bytes: "")
        }

        let testTargetPath = manifestPath.parentDirectory.appending(components: "Tests", testTargetName)
        if !fs.exists(testTargetPath) {
            let file = testTargetPath.appending(components: testTargetName + ".swift")
            try fs.createDirectory(testTargetPath)
            try fs.writeFileContents(file) {
                $0 <<< """
                import XCTest
                @testable import \(targetName)

                final class \(testTargetName): XCTestCase {
                    func testExample() {
                    }
                }
                """
            }
        }
    }
}

extension Array where Element == TargetDescription.Dependency {
    func containsDependency(_ other: String) -> Bool {
        return self.contains {
            switch $0 {
            case .target(name: let name, condition: _),
                 .product(name: let name, package: _, condition: _),
                 .byName(name: let name, condition: _):
                return name == other
            }
        }
    }
}

/// The types of target.
public enum TargetType {
    case regular
    case test

    /// The name of the factory method for a target type.
    var factoryMethodName: String {
        switch self {
        case .regular: return "target"
        case .test: return "testTarget"
        }
    }
}

public enum PackageDependencyRequirement: Equatable {
    case exact(String)
    case revision(String)
    case branch(String)
    case upToNextMajor(String)
    case upToNextMinor(String)
    case localPackage

    var ref: String? {
        switch self {
        case .exact(let ref): return ref
        case .revision(let ref): return ref
        case .branch(let ref): return ref
        case .upToNextMajor(let ref): return ref
        case .upToNextMinor(let ref): return ref
        case .localPackage: return nil
        }
    }
}

extension ProductType {
    var isLibrary: Bool {
        switch self {
        case .library:
            return true
        case .executable, .test:
            return false
        }
    }
}

/// The global context for package editor.
public final class PackageEditorContext {
    /// Path to the package manifest.
    let manifestPath: AbsolutePath

    /// The manifest loader.
    let manifestLoader: ManifestLoaderProtocol

    /// The repository manager.
    let repositoryManager: RepositoryManager

    /// The file system in use.
    let fs: FileSystem

    public init(manifestPath: AbsolutePath,
                repositoryManager: RepositoryManager,
                toolchain: UserToolchain,
                fs: FileSystem = localFileSystem) throws {
        self.manifestPath = manifestPath
        self.repositoryManager = repositoryManager
        self.fs = fs

        self.manifestLoader = ManifestLoader(manifestResources: toolchain.manifestResources)
    }

    /// Load the manifest at the given path.
    func loadManifest(
        at path: AbsolutePath,
        fs: FileSystem? = nil
    ) throws -> Manifest {
        let fs = fs ?? self.fs

        let toolsVersion = try ToolsVersionLoader().load(
            at: path, fileSystem: fs)

        guard toolsVersion >= .v5_2 else {
            throw StringError("mechanical manifest editing operations are only supported for packages with swift-tools-version 5.2 and later")
        }

        return try manifestLoader.load(
            package: path,
            baseURL: path.pathString,
            toolsVersion: toolsVersion,
            packageKind: .local,
            fileSystem: fs
        )
    }
}
