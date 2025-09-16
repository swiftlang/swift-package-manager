//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@_spi(FixItApplier) import SwiftIDEUtils
@_spi(PackageRefactor) import SwiftRefactor
import SwiftSyntax

package extension [SourceEdit] {
    /// Apply the edits for the given manifest to the specified file system,
    /// updating the manifest to the given manifest
    func applyEdits(
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
            edits: self,
            to: manifest
        )
        try filesystem.writeFileContents(
            manifestPath,
            string: updatedManifestSource
        )
        if verbose {
            print(" done.")
        }
    }
}
