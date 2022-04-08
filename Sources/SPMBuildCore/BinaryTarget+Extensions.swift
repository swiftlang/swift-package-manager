//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Basics
import PackageModel
import PackageGraph
import TSCBasic

import struct TSCUtility.Triple

/// Information about a library from a binary dependency.
public struct LibraryInfo: Equatable {
    /// The path to the binary.
    public let libraryPath: AbsolutePath

    /// The path to the headers directory, if one exists.
    public let headersPath: AbsolutePath?
}


/// Information about an executable from a binary dependency.
public struct ExecutableInfo: Equatable {
    /// The tool name
    public let name: String

    /// The path to the executable.
    public let executablePath: AbsolutePath
}


extension BinaryTarget {
    
    public func parseXCFrameworks(for triple: Triple, fileSystem: FileSystem) throws -> [LibraryInfo] {
        // At the moment we return at most a single library.
        let metadata = try XCFrameworkMetadata.parse(fileSystem: fileSystem, rootPath: self.artifactPath)
        // Filter the libraries that are relevant to the triple.
        // FIXME: this filter needs to become more sophisticated
        guard let library = metadata.libraries.first(where: {
            $0.platform == triple.os.asXCFrameworkPlatformString &&
            $0.architectures.contains(triple.arch.rawValue)
        }) else {
            return []
        }
        // Construct a LibraryInfo for the library.
        let libraryDir = self.artifactPath.appending(component: library.libraryIdentifier)
        let libraryFile = AbsolutePath(library.libraryPath, relativeTo: libraryDir)
        let headersDir = library.headersPath.map { AbsolutePath($0, relativeTo: libraryDir) }
        return [LibraryInfo(libraryPath: libraryFile, headersPath: headersDir)]
    }

    public func parseArtifactArchives(for triple: Triple, fileSystem: FileSystem) throws -> [ExecutableInfo] {
        // The host triple might contain a version which we don't want to take into account here.
        let versionLessTriple = try triple.withoutVersion()
        // We return at most a single variant of each artifact.
        let metadata = try ArtifactsArchiveMetadata.parse(fileSystem: fileSystem, rootPath: self.artifactPath)
        // Currently we filter out everything except executables.
        // TODO: Add support for libraries
        let executables = metadata.artifacts.filter { $0.value.type == .executable }
        // Construct an ExecutableInfo for each matching variant.
        return executables.flatMap { entry in
            // FIXME: this filter needs to become more sophisticated
            entry.value.variants.filter {
                return $0.supportedTriples.contains(versionLessTriple)
            }.map{
                ExecutableInfo(name: entry.key, executablePath: AbsolutePath($0.path, relativeTo: self.artifactPath))
            }
        }
    }
}

fileprivate extension Triple {
    func withoutVersion() throws -> Triple {
        if isDarwin() {
            let stringWithoutVersion = tripleString(forPlatformVersion: "")
            return try Triple(stringWithoutVersion)
        } else {
            return self
        }
    }
}

fileprivate extension Triple.OS {
    /// Returns a representation of the receiver that can be compared with platform strings declared in an XCFramework.
    var asXCFrameworkPlatformString: String? {
        switch self {
        case .darwin, .linux, .wasi, .windows, .openbsd:
            return nil // XCFrameworks do not support any of these platforms today.
        case .macOS:
            return "macos"
        }
    }
}
