//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

import struct Foundation.URL
import protocol TSCBasic.FileSystem
import struct TSCBasic.RegEx

/// Represents an `.artifactbundle` on the filesystem that contains a Swift SDK.
public struct SwiftSDKBundle {
    public struct Variant: Equatable {
        let metadata: ArtifactsArchiveMetadata.Variant
        let swiftSDKs: [SwiftSDK]
    }

    // Path to the bundle root directory.
    public let path: AbsolutePath

    /// Mapping of artifact IDs to variants available for a corresponding artifact.
    public internal(set) var artifacts = [String: [Variant]]()

    /// Name of the Swift SDK bundle that can be used to distinguish it from other bundles.
    public var name: String { path.basename }
}

extension SwiftSDKBundle.Variant {
    /// Whether the given host triple is supported by this SDK variant
    internal func isSupporting(hostTriple: Triple) -> Bool {
        guard let supportedTriples = metadata.supportedTriples else {
            // No supportedTriples means the SDK can be universally usable
            return true
        }
        return supportedTriples.contains(where: { variantTriple in
            hostTriple.isRuntimeCompatible(with: variantTriple)
        })
    }
}

extension [SwiftSDKBundle] {
    /// Select a Swift SDK with a given artifact ID from a `self` array of available Swift SDKs.
    /// - Parameters:
    ///   - id: artifact ID of the Swift SDK to look up.
    ///   - hostTriple: triple of the machine on which the Swift SDK is building.
    ///   - targetTriple: triple of the machine for which the Swift SDK is building.
    /// - Returns: ``SwiftSDK`` value with a given artifact ID, `nil` if none found.
    public func selectSwiftSDK(id: String, hostTriple: Triple?, targetTriple: Triple) -> SwiftSDK? {
        for bundle in self {
            for (artifactID, variants) in bundle.artifacts {
                guard artifactID == id else {
                    continue
                }

                for variant in variants {
                    if let hostTriple {
                        guard variant.isSupporting(hostTriple: hostTriple) else {
                            continue
                        }
                    }

                    return variant.swiftSDKs.first { $0.targetTriple == targetTriple }
                }
            }
        }

        return nil
    }

    /// Select Swift SDKs matching a given selector and host triple from a `self` array of available Swift SDKs.
    /// - Parameters:
    ///   - selector: either an artifact ID or target triple to filter with.
    ///   - hostTriple: triple of the host building with these Swift SDKs.
    ///   - observabilityScope: observability scope to log warnings about multiple matches.
    /// - Returns: ``SwiftSDK`` value matching `query` either by artifact ID or target triple, `nil` if none found.
    func selectSwiftSDK(
        matching selector: String,
        hostTriple: Triple,
        observabilityScope: ObservabilityScope
    ) -> SwiftSDK? {
        var matchedByID: (path: AbsolutePath, variant: SwiftSDKBundle.Variant, swiftSDK: SwiftSDK)?
        var matchedByTriple: (path: AbsolutePath, variant: SwiftSDKBundle.Variant, swiftSDK: SwiftSDK)?

        for bundle in self {
            for (artifactID, variants) in bundle.artifacts {
                for variant in variants {
                    guard variant.isSupporting(hostTriple: hostTriple) else { continue }

                    for swiftSDK in variant.swiftSDKs {
                        if artifactID == selector {
                            if let matchedByID {
                                observabilityScope.emit(
                                    warning:
                                    """
                                    multiple Swift SDKs match ID `\(artifactID)` and host triple \(
                                        hostTriple.tripleString
                                    ), selected one at \(
                                        matchedByID.path.appending(matchedByID.variant.metadata.path)
                                    )
                                    """
                                )
                            } else {
                                matchedByID = (bundle.path, variant, swiftSDK)
                            }
                        }

                        if swiftSDK.targetTriple?.tripleString == selector {
                            if let matchedByTriple {
                                observabilityScope.emit(
                                    warning:
                                    """
                                    multiple Swift SDKs match target triple `\(selector)` and host triple \(
                                        hostTriple.tripleString
                                    ), selected one at \(
                                        matchedByTriple.path.appending(matchedByTriple.variant.metadata.path)
                                    )
                                    """
                                )
                            } else {
                                matchedByTriple = (bundle.path, variant, swiftSDK)
                            }
                        }
                    }
                }
            }
        }

        if let matchedByID, let matchedByTriple, matchedByID != matchedByTriple {
            observabilityScope.emit(
                warning:
                """
                multiple Swift SDKs match the query `\(selector)` and host triple \(
                    hostTriple.tripleString
                ), selected one at \(matchedByID.path.appending(matchedByID.variant.metadata.path))
                """
            )
        }

        return matchedByID?.swiftSDK ?? matchedByTriple?.swiftSDK
    }

    public var sortedArtifactIDs: [String] {
        self.flatMap(\.artifacts.keys).sorted()
    }
}
