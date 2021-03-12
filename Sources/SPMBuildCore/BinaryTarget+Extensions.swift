/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Basics
import PackageModel
import PackageGraph
import TSCBasic
import TSCUtility


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
    
    public func parseXCFrameworks(for buildParameters: BuildParameters, fileSystem: FileSystem) throws -> [LibraryInfo] {
        let metadata = try XCFrameworkMetadata.parse(fileSystem: fileSystem, rootPath: self.artifactPath)
        guard let library = metadata.libraries.first(where: {
            $0.platform == buildParameters.triple.os.asXCFrameworkPlatformString &&
            $0.architectures.contains(buildParameters.triple.arch.rawValue)
        }) else {
            return []
        }
        let libraryDir = self.artifactPath.appending(component: library.libraryIdentifier)
        let libraryFile = libraryDir.appending(RelativePath(library.libraryPath))
        let headersDir = library.headersPath.map({ libraryDir.appending(RelativePath($0)) })
        return [LibraryInfo(libraryPath: libraryFile, headersPath: headersDir)]
    }

    public func parseArtifactArchives(for buildParameters: BuildParameters, fileSystem: FileSystem) throws -> [ExecutableInfo] {
        let metadata = try ArtifactsArchiveMetadata.parse(fileSystem: fileSystem, rootPath: self.artifactPath)
        // filter the artifacts that are relevant to the triple
        // FIXME: this filter needs to become more sophisticated
        let supportedArtifacts = metadata.artifacts.filter { $0.value.variants.contains(where: { $0.supportedTriples.contains(buildParameters.triple) }) }
        // TODO: add support for libraries
        let executables = supportedArtifacts.filter { $0.value.type == .executable }
        return executables.flatMap { entry in
            entry.value.variants.map{ ExecutableInfo(name: entry.key, executablePath: self.artifactPath.appending(RelativePath($0.path))) }
        }
    }
}

fileprivate extension Triple.OS {
    /// Returns a representation of the receiver that can be compared with platform strings declared in an XCFramework.
    var asXCFrameworkPlatformString: String? {
        switch self {
        case .darwin, .linux, .wasi, .windows:
            return nil // XCFrameworks do not support any of these platforms today.
        case .macOS:
            return "macos"
        }
    }
}
