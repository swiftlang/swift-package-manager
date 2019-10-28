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
    public convenience init(buildDir: AbsolutePath) throws {
        self.init(context: try PackageEditorContext(buildDir: buildDir))
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
    public func addPackageDependency(options: Options.AddPackageDependency) throws {
        var options = options

        // Validate that the package doesn't already contain this dependency.
        // FIXME: We need to handle version-specific manifests.
        let loadedManifest = try context.loadManifest(at: options.manifestPath.parentDirectory)
        let containsDependency = loadedManifest.dependencies.contains {
            return PackageReference.computeIdentity(packageURL: options.url) == PackageReference.computeIdentity(packageURL: $0.url)
        }
        guard !containsDependency else {
            throw StringError("Already has dependency \(options.url)")
        }

        // If the input URL is a path, force the requirement to be a local package.
        if TSCUtility.URL.scheme(options.url) == nil {
            assert(options.requirement == nil || options.requirement == .localPackage)
            options.requirement = .localPackage
        }

        // Load the dependency manifest depending on the inputs.
        let dependencyManifest: Manifest
        let requirement: PackageDependencyRequirement
        if options.requirement == .localPackage {
            // For local packages, load the manifest and get the first library product name.
            let path = AbsolutePath(options.url, relativeTo: fs.currentWorkingDirectory!)
            dependencyManifest = try context.loadManifest(at: path)
            requirement = .localPackage
        } else {
            // Otherwise, first lookup the dependency.
            let spec = RepositorySpecifier(url: options.url)
            let handle = try await{ context.repositoryManager.lookup(repository: spec, completion: $0) }
            let repo = try handle.open()

            // Compute the requirement.
            if let inputRequirement = options.requirement {
                requirement = inputRequirement
            } else {
                // Use the latest version or the master branch.
                let versions = repo.tags.compactMap{ Version(string: $0) }
                let latestVersion = versions.filter({ $0.prereleaseIdentifiers.isEmpty }).max() ?? versions.max()
                requirement = latestVersion.map{ PackageDependencyRequirement.upToNextMajor($0.description) } ?? PackageDependencyRequirement.branch("master")
            }

            // Load the manifest.
            let revision = try repo.resolveRevision(identifier: requirement.ref!)
            let repoFS = try repo.openFileView(revision: revision)
            dependencyManifest = try context.loadManifest(at: .root, fs: repoFS)
        }

        // Add the package dependency.
        let manifestContents = try fs.readFileContents(options.manifestPath).cString
        let editor = try ManifestRewriter(manifestContents)
        try editor.addPackageDependency(url: options.url, requirement: requirement)

        // Add the product in the first regular target, if possible.
        let productName = dependencyManifest.products.filter{ $0.type.isLibrary }.map{ $0.name }.first
        let destTarget = loadedManifest.targets.filter{ $0.type == .regular }.first
        if let product = productName,
            let destTarget = destTarget,
            !destTarget.dependencies.containsDependency(product) {
            try editor.addTargetDependency(target: destTarget.name, dependency: product)
        }

        // FIXME: We should verify our edits by loading the edited manifest before writing it to disk.
        try fs.writeFileContents(options.manifestPath, bytes: ByteString(encodingAsUTF8: editor.editedManifest))
    }

    /// Add a new target.
    public func addTarget(options: Options.AddTarget) throws {
        let manifest = options.manifestPath
        let targetName = options.targetName
        let testTargetName = targetName + "Tests"

        // Validate that the package doesn't already contain this dependency.
        // FIXME: We need to handle version-specific manifests.
        let loadedManifest = try context.loadManifest(at: options.manifestPath.parentDirectory)
        if loadedManifest.targets.contains(where: { $0.name == targetName }) {
            throw StringError("Already has a target named \(targetName)")
        }

        let manifestContents = try fs.readFileContents(options.manifestPath).cString
        let editor = try ManifestRewriter(manifestContents)
        try editor.addTarget(targetName: targetName)
        try editor.addTarget(targetName: testTargetName, type: .test)
        try editor.addTargetDependency(target: testTargetName, dependency: targetName)

        // FIXME: We should verify our edits by loading the edited manifest before writing it to disk.
        try fs.writeFileContents(manifest, bytes: ByteString(encodingAsUTF8: editor.editedManifest))

        // Write template files.
        let targetPath = manifest.parentDirectory.appending(components: "Sources", targetName)
        if !localFileSystem.exists(targetPath) {
            let file = targetPath.appending(components: targetName + ".swift")
            try fs.createDirectory(targetPath)
            try fs.writeFileContents(file, bytes: "")
        }

        let testTargetPath = manifest.parentDirectory.appending(components: "Tests", testTargetName)
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
            case .target(let name), .product(let name, _), .byName(let name):
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

public enum Options {
    public struct AddPackageDependency {
        public var manifestPath: AbsolutePath
        public var url: String
        public var requirement: PackageDependencyRequirement?

        public init(
            manifestPath: AbsolutePath,
            url: String,
            requirement: PackageDependencyRequirement? = nil
        ) {
            self.manifestPath = manifestPath
            self.url = url
            self.requirement = requirement
        }
    }

    public struct AddTarget {
        public var manifestPath: AbsolutePath
        public var targetName: String
        public var targetType: TargetType

        public init(
            manifestPath: AbsolutePath,
            targetName: String,
            targetType: TargetType = .regular
        ) {
            self.manifestPath = manifestPath
            self.targetName = targetName
            self.targetType = targetType
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

    /// Path to the build directory of the package.
    let buildDir: AbsolutePath

    /// The manifest loader.
    let manifestLoader: ManifestLoaderProtocol

    /// The repository manager.
    let repositoryManager: RepositoryManager

    /// The file system in use.
    let fs: FileSystem

    public init(buildDir: AbsolutePath, fs: FileSystem = localFileSystem) throws {
        self.buildDir = buildDir
        self.fs = fs

        // Create toolchain.
        let hostToolchain = try UserToolchain(destination: .hostDestination())
        self.manifestLoader = ManifestLoader(manifestResources: hostToolchain.manifestResources)

        let repositoriesPath = buildDir.appending(component: "repositories")
        self.repositoryManager = RepositoryManager(
            path: repositoriesPath,
            provider: GitRepositoryProvider()
        )
    }

    /// Load the manifest at the given path.
    func loadManifest(
        at path: AbsolutePath,
        fs: FileSystem? = nil
    ) throws -> Manifest {
        let fs = fs ?? self.fs

        let toolsVersion = try ToolsVersionLoader().load(
            at: path, fileSystem: fs)

        return try manifestLoader.load(
            package: path,
            baseURL: path.description,
            version: nil,
            toolsVersion: toolsVersion,
            fileSystem: fs
        )
    }
}
