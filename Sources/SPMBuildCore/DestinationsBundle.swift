//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import TSCBasic

/// Represents an `.artifactbundle` on the filesystem that contains cross-compilation destinations.
public struct DestinationsBundle {
    public struct Variant {
        let metadata: ArtifactsArchiveMetadata.Variant
        let destination: Destination
    }

    let path: AbsolutePath

    /// Mapping of artifact IDs to variants available for a corresponding artifact.
    public fileprivate(set) var artifacts = [String: [Variant]]()

    /// Parses metadata of an `.artifactbundle` and validates it as a bundle containing
    /// cross-compilation destinations.
    /// - Parameters:
    ///   - bundlePath: path to the bundle root directory.
    ///   - fileSystem: filesystem containing the bundle.
    ///   - observabilityScope: observability scope to log validation warnings.
    /// - Returns: Validated `DestinationsBundle` containing validated `Destination` values for
    /// each artifact and its variants.
    public static func parseAndValidate(
        bundlePath: AbsolutePath,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws -> Self {
        let parsedManifest = try ArtifactsArchiveMetadata.parse(
            fileSystem: fileSystem,
            rootPath: bundlePath
        )

        return try parsedManifest.validateDestinationsBundle(
            bundlePath: bundlePath,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
    }
}

private extension ArtifactsArchiveMetadata {
    func validateDestinationsBundle(
        bundlePath: AbsolutePath,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws -> DestinationsBundle {
        var result = DestinationsBundle(path: bundlePath)

        for (artifactID, artifactMetadata) in artifacts
        where artifactMetadata.type == .crossCompilationDestination {
            var variants = [DestinationsBundle.Variant]()

            for variant in artifactMetadata.variants {
                let destinationJSONPath = try bundlePath
                    .appending(RelativePath(validating: variant.path))
                    .appending(component: "destination.json")

                guard fileSystem.exists(destinationJSONPath) else {
                    observabilityScope.emit(
                        .warning(
                            """
                            Destination metadata file not found at \(
                                destinationJSONPath
                            ) for a variant of artifact \(artifactID)
                            """
                        )
                    )

                    continue
                }

                do {
                    let destination = try Destination(
                        fromFile: destinationJSONPath, fileSystem: fileSystem
                    )

                    variants.append(.init(metadata: variant, destination: destination))
                } catch {
                    observabilityScope.emit(
                        .warning(
                            "Couldn't parse destination metadata at \(destinationJSONPath): \(error)"
                        )
                    )
                }
            }

            result.artifacts[artifactID] = variants
        }

        return result
    }
}
