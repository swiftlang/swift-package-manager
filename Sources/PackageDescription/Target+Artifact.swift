//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension Target {
    /// Creates an artifact target that references a remote archive.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - url: The URL to the binary artifact. This URL must point to an archive
    ///     file that contains a binary artifact in its root directory.
    ///   - checksum: The checksum of the archive file that contains the binary
    ///     artifact.
    @available(_PackageDescription, introduced: 999.0)
    public static func artifactTarget(
        name: String,
        url: String,
        checksum: String
    ) -> Target {
        return Target(
            name: name,
            dependencies: [],
            path: nil,
            url: url,
            exclude: [],
            sources: nil,
            publicHeadersPath: nil,
            type: .artifact,
            packageAccess: false,
            checksum: checksum)
    }

    /// Creates an artifact target that references a directory or a file on disk.
    ///
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - path: The path to the artifact. This path can point directly to
    ///     a directory or to an archive file that contains the artifact at its root.
    @available(_PackageDescription, introduced: 999.0)
    public static func artifactTarget(
        name: String,
        path: String
    ) -> Target {
        return Target(
            name: name,
            dependencies: [],
            path: path,
            exclude: [],
            sources: nil,
            publicHeadersPath: nil,
            type: .artifact,
            packageAccess: false)
    }

}
