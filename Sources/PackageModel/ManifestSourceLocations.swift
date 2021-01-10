/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

// The SourceLoc structs in this file abstractly describe specific positions in
// the manifest. A client able to parse the manifest can use this information to
// resolve to a line and column in the source.

/// Describes the location of a `.dependency(...)` declaration in the manifest source.
public struct DependencyDeclSourceLoc: DiagnosticLocation {
    public var manifest: Manifest
    public var dependency: PackageDependencyDescription
    public var fileSystem: FileSystem

    public init(manifest: Manifest, dependency: PackageDependencyDescription, fileSystem: FileSystem) {
        self.manifest = manifest
        self.dependency = dependency
        self.fileSystem = fileSystem
    }

    public var description: String {
        "\(manifest.path):dependency(\(dependency.name))"
    }
}
