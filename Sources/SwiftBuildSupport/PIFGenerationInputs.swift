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
import PackageGraph
import PackageLoading
import PackageModel

public struct PIFGenerationInputs: Sendable {
    private var watchedDirectoryStructures: Set<AbsolutePath>
    private var watchedFiles: Set<AbsolutePath>
    private var watchedPackageRootDirectories: Set<AbsolutePath>

    package init(
        watchedDirectories: Set<AbsolutePath>,
        watchedFiles: Set<AbsolutePath>,
        watchedPackageRootDirectories: Set<AbsolutePath>
    ) {
        self.watchedDirectoryStructures = watchedDirectories
        self.watchedFiles = watchedFiles
        self.watchedPackageRootDirectories = watchedPackageRootDirectories
    }

    package func creationOrDeletionAffectsPIF(_ path: AbsolutePath) -> Bool {
        if self.modificationAffectsPIF(path) {
            return true
        }
        return self.watchedDirectoryStructures.contains { path.isDescendantOfOrEqual(to: $0) }
    }

    package func modificationAffectsPIF(_ path: AbsolutePath) -> Bool {
        if self.watchedFiles.contains(path) {
            return true
        }
        return self.watchedPackageRootDirectories.contains(path.parentDirectory) && Self.isManifestFileName(path.basename)
    }

    private static let versionSpecificManifestRegex = #/^Package@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?\.swift$/#
    private static func isManifestFileName(_ name: String) -> Bool {
        name == Manifest.filename || name.wholeMatch(of: versionSpecificManifestRegex) != nil
    }

    private static let predefinedTargetDirectories: Set<String> = Set(
        PackageBuilder.predefinedSourceDirectories
            + PackageBuilder.predefinedTestDirectories
            + PackageBuilder.predefinedPluginDirectories
    )

    public static func fallbackInputs(packageRoot: AbsolutePath) -> PIFGenerationInputs {
        PIFGenerationInputs(
            watchedDirectories: [packageRoot],
            watchedFiles: [packageRoot.appending("Package.resolved")],
            watchedPackageRootDirectories: [packageRoot]
        )
    }

    package init(
        graph: ModulesGraph,
        modulesAndProducts: [PackagePIFBuilder.ModuleOrProduct],
        pluginWorkingDirectory: AbsolutePath,
        pkgConfigDirectories: [AbsolutePath]
    ) {
        var directories: Set<AbsolutePath> = []
        var files: Set<AbsolutePath> = []
        var packageDirectories: Set<AbsolutePath> = []

        for package in graph.packages {
            packageDirectories.insert(package.path)
            files.insert(package.manifest.path)

            if package.manifest.packageKind.isRoot {
                files.insert(package.path.appending("Package.resolved"))
            }

            for module in package.modules {
                directories.insert(module.sources.root)
            }

            directories.formUnion(Self.predefinedTargetDirectories.map { package.path.appending(component: $0) })
            for target in package.manifest.targets {
                guard let path = target.path, let relativePath = try? RelativePath(validating: path) else {
                    continue
                }
                directories.insert(package.path.appending(relativePath))
            }
        }

        for moduleOrProduct in modulesAndProducts {
            files.formUnion(moduleOrProduct.buildToolPluginInputs)
        }
        directories.insert(pluginWorkingDirectory.appending("outputs"))

        directories.formUnion(pkgConfigDirectories)

        self.init(watchedDirectories: directories, watchedFiles: files, watchedPackageRootDirectories: packageDirectories)
    }
}

