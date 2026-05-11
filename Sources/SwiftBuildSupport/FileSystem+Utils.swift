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

import struct Basics.AbsolutePath
import protocol Basics.FileSystem
import var Basics.localFileSystem
import class Basics.ObservabilityScope

package func createBuildSymbolicLinks(
    _ path: Basics.AbsolutePath,
    pointingAt: Basics.AbsolutePath,
    fileSystem: FileSystem = localFileSystem,
    observabilityScope: ObservabilityScope,
) {
    if fileSystem.exists(path, followSymlink: true) {
        do {
            // This does not delete the directory pointed to by the symbolic link
            try fileSystem.removeFileTree(path)
        } catch {
            observabilityScope.emit(
                warning: "unable to delete \(path), skip creating symbolic link",
                underlyingError: error
            )
        }
    }

    do {
        try fileSystem.createSymbolicLink(
            path,
            pointingAt: pointingAt,
            relative: true,
        )
    } catch {
        observabilityScope.emit(
            warning: "unable to create symbolic link at \(path)",
            underlyingError: error
        )
    }
}
