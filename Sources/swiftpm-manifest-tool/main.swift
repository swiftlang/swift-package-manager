/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019-2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import SPMPackageEditor
import Workspace
import PackageModel

import ArgumentParser

/// The root manifest editor command.
struct ManifestTool: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "swiftpm-manifest-tool",
        abstract: "Mechanically edit SwiftPM manifests.",
        subcommands: [AddPackageDependency.self, AddTarget.self])
}

ManifestTool.main()

// MARK: - Subcommands

/// Options shared by manifest editing subcommands.
struct ManifestToolOptions: ParsableArguments {
    @Option
    var buildPath: AbsolutePath?
}

/// Implements the add-package-dependency subcommand.
struct AddPackageDependency: ParsableCommand {

    @Argument
    var dependencyURL: String

    @OptionGroup
    var manifestToolOptions: ManifestToolOptions

    mutating func run() throws {
        guard let cwd = localFileSystem.currentWorkingDirectory else {
            throw ValidationError("error: couldn't determine the current working directory")
        }
        guard let packageRoot = findPackageRoot() else {
            throw ValidationError("error: couldn't find a package manifest")
        }
        let buildPath = getEnvBuildPath(workingDir: cwd) ??
            manifestToolOptions.buildPath ??
            packageRoot.appending(component: ".build")
        let editor = try PackageEditor(manifestPath: packageRoot.appending(component: Manifest.filename),
                                       buildDir: buildPath,
                                       toolchain: UserToolchain(destination: try Destination.hostDestination()))
        try editor.addPackageDependency(url: dependencyURL, requirement: nil)
    }
}

struct AddTarget: ParsableCommand {

    @Argument
    var targetName: String

    @Option
    var targetType: TargetType?

    @OptionGroup
    var manifestToolOptions: ManifestToolOptions

    mutating func run() throws {
        guard let cwd = localFileSystem.currentWorkingDirectory else {
            throw ValidationError("error: couldn't determine the current working directory")
        }
        guard let packageRoot = findPackageRoot() else {
            throw ValidationError("error: couldn't find a package manifest")
        }
        let buildPath = getEnvBuildPath(workingDir: cwd) ??
            manifestToolOptions.buildPath ??
            packageRoot.appending(component: ".build")
        let editor = try PackageEditor(manifestPath: packageRoot.appending(component: Manifest.filename),
                                       buildDir: buildPath,
                                       toolchain: UserToolchain(destination: try Destination.hostDestination()))
        try editor.addTarget(name: targetName, type: targetType)
    }
}

// MARK: - Utilities

/// Returns path of the nearest directory containing the manifest file w.r.t
/// current working directory.
fileprivate func findPackageRoot() -> AbsolutePath? {
    guard var root = localFileSystem.currentWorkingDirectory else {
        return nil
    }
    // FIXME: It would be nice to move this to a generalized method which takes path and predicate and
    // finds the lowest path for which the predicate is true.
    while !localFileSystem.isFile(root.appending(component: Manifest.filename)) {
        root = root.parentDirectory
        guard !root.isRoot else {
            return nil
        }
    }
    return root
}

/// Returns the build path from the environment, if present.
fileprivate func getEnvBuildPath(workingDir: AbsolutePath) -> AbsolutePath? {
    // Don't rely on build path from env for SwiftPM's own tests.
    guard ProcessEnv.vars["SWIFTPM_TESTS_MODULECACHE"] == nil else { return nil }
    guard let env = ProcessEnv.vars["SWIFTPM_BUILD_DIR"] else { return nil }
    return AbsolutePath(env, relativeTo: workingDir)
}

extension AbsolutePath: ExpressibleByArgument {
    public init?(argument: String) {
        if let cwd = localFileSystem.currentWorkingDirectory {
            self.init(argument, relativeTo: cwd)
        } else {
            guard let path = try? AbsolutePath(validating: argument) else {
                return nil
            }
            self = path
        }
    }

    public static var defaultCompletionKind: CompletionKind {
        // This type is most commonly used to select a directory, not a file.
        // Specify '.file()' in an argument declaration when necessary.
        .directory
    }
}

extension TargetType: ExpressibleByArgument {
    public init?(argument: String) {
        switch argument {
        case "regular":
            self = .regular
        case "test":
            self = .test
        default:
            return nil
        }
    }

    public static var defaultCompletionKind: CompletionKind {
        .list(["regular", "test"])
    }
}
