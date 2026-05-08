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
    public func selectSwiftSDK(id: String, hostTriple: Triple, targetTriple: Triple) -> SwiftSDK? {
        for bundle in self {
            for (artifactID, variants) in bundle.artifacts {
                guard artifactID == id else {
                    continue
                }

                for variant in variants {
                    guard variant.isSupporting(hostTriple: hostTriple) else {
                        continue
                    }

                    return variant.swiftSDKs.first { $0.targetTriple?.tripleString == targetTriple.tripleString }
                }
            }
        }

        return nil
    }

    /// Select Swift SDKs matching a given selector and host triple from a `self` array of available Swift SDKs.
    /// - Parameters:
    ///   - selector: either an artifact ID or target triple to filter with.
    ///   - hostTriple: triple of the host building with these Swift SDKs.
    /// - Returns: a tuple containing all `selector` matches to the artifact ID or target triple,
    ///            including the corresponding artifact ID for each target triple matched
    func selectSwiftSDK(
        matching selector: String,
        hostTriple: Triple
    ) -> (idMatches: [SwiftSDK], tripleMatches: [String: SwiftSDK]) {
        var idHits: [SwiftSDK] = []
        var tripleHits: [String: SwiftSDK] = [:]

        for bundle in self {
            for (artifactID, variants) in bundle.artifacts {
                for variant in variants {
                    guard variant.isSupporting(hostTriple: hostTriple) else { continue }

                    for swiftSDK in variant.swiftSDKs {
                        // All artifact IDs are checked by installIfValid() to be
                        // unique, but the selected ID must only have one target triple,
                        // in this method where no target triple is specified with the ID.
                        if artifactID == selector {
                            idHits.append(swiftSDK)
                        }
                        // Multiple SDKs can vend the same triple, so list them all and
                        // return the corresponding artifact ID also.
                        if swiftSDK.targetTriple?.tripleString == selector {
                            tripleHits[artifactID] = swiftSDK
                        }
                    }
                }
            }
        }
        return (idMatches: idHits, tripleMatches: tripleHits)
    }

    public var sortedArtifactIDs: [String] {
        self.flatMap(\.artifacts.keys).sorted()
    }
}
