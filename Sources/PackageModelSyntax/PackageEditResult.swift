//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@_spi(FixItApplier) import SwiftIDEUtils
import SwiftSyntax

/// The result of editing a package, including any edits to the package
/// manifest and any new files that are introduced.
public struct PackageEditResult {
    /// Edits to perform to the package manifest.
    public var manifestEdits: [SourceEdit] = []

    /// Auxiliary files to write.
    public var auxiliaryFiles: [(RelativePath, SourceFileSyntax)] = []
}

extension PackageEditResult {
    /// Apply the edits for the given manifest to the specified file system,
    /// updating the manifest to the given manifest
    public func applyEdits(
        to filesystem: any FileSystem,
        manifest: SourceFileSyntax,
        manifestPath: AbsolutePath,
        verbose: Bool
    ) throws {
        let rootPath = manifestPath.parentDirectory

        // Update the manifest
        if verbose {
            print("Updating package manifest at \(manifestPath.relative(to: rootPath))...", terminator: "")
        }

        let updatedManifestSource = FixItApplier.apply(
            edits: manifestEdits,
            to: manifest
        )
        try filesystem.writeFileContents(
            manifestPath,
            string: updatedManifestSource
        )
        if verbose {
            print(" done.")
        }

        // Write all of the auxiliary files.
        for (auxiliaryFileRelPath, auxiliaryFileSyntax) in auxiliaryFiles {
            // If the file already exists, skip it.
            let filePath = rootPath.appending(auxiliaryFileRelPath)
            if filesystem.exists(filePath) {
                if verbose {
                    print("Skipping \(filePath.relative(to: rootPath)) because it already exists.")
                }

                continue
            }

            // If the directory does not exist yet, create it.
            let fileDir = filePath.parentDirectory
            if !filesystem.exists(fileDir) {
                if verbose {
                    print("Creating directory \(fileDir.relative(to: rootPath))...", terminator: "")
                }

                try filesystem.createDirectory(fileDir, recursive: true)

                if verbose {
                    print(" done.")
                }
            }

            // Write the file.
            if verbose {
                print("Writing \(filePath.relative(to: rootPath))...", terminator: "")
            }

            try filesystem.writeFileContents(
                filePath,
                string: auxiliaryFileSyntax.description
            )

            if verbose {
                print(" done.")
            }
        }
    }

}
