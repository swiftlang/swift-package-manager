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
import enum TSCBasic.FileMode

/// Keeps generated Swift sources read-only between builds while allowing build
/// tool plugins to replace them when they run again.
package struct GeneratedSourceFileProtection {
    private let fileSystem: any FileSystem
    private let outputDirectory: AbsolutePath

    package init(fileSystem: any FileSystem, pluginWorkDirectory: AbsolutePath) {
        self.fileSystem = fileSystem
        self.outputDirectory = pluginWorkDirectory.appending("outputs")
    }

    /// Restores write access before prebuild and build commands may regenerate
    /// their declared outputs.
    package func prepareForBuild() throws {
        try self.setGeneratedSourcesFileMode(.userWritable)
    }

    /// Removes write access from generated Swift sources after the build has
    /// completed, including builds that fail while compiling generated code.
    package func protectGeneratedSources() throws {
        try self.setGeneratedSourcesFileMode(.userUnWritable)
    }

    private func setGeneratedSourcesFileMode(_ mode: FileMode) throws {
        guard self.fileSystem.exists(self.outputDirectory) else {
            return
        }

        for path in try walk(self.outputDirectory, fileSystem: self.fileSystem) {
            guard
                path.extension == "swift",
                self.fileSystem.isFile(path),
                !self.fileSystem.isSymlink(path)
            else {
                continue
            }
            try self.fileSystem.chmod(mode, path: path)
        }
    }
}
