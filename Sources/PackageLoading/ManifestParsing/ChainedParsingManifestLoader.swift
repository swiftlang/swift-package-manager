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

#if !DISABLE_PARSING_MANIFEST_LOADER
import Basics
import Dispatch
import Foundation
import PackageModel
import SourceControl

import SwiftDiagnostics
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

import struct TSCBasic.ByteString

import struct TSCUtility.Version

/// Manifest loader that chains together a parsing manifest loader (which
/// parses the manifest source directly) and an another manifest loader
/// (e.g., that executes the manifest). It can use the parsing manifest
/// loader when that succeeds, or cross-check the results of the parsing
/// manifest loader against the other manifest loader to verify that they
/// produce the same results.
public final class ChainedParsingManifestLoader: ManifestLoaderProtocol {
    let parsingLoader: ParsingManifestLoader
    let executingLoader: any ManifestLoaderProtocol

    /// Whether to show the limitations that prevent us from using the
    /// results of the parsing loader.
    let showLimitations: Bool

    /// Whether to cross-check the results of the two loaders. Otherwise,
    /// the results will be taken from the parsing loader if it succeeds,
    /// and the executing loader otherwise.
    let crosscheck: Bool

    public init(
        parsingLoader: ParsingManifestLoader,
        executingLoader: any ManifestLoaderProtocol,
        showLimitations: Bool,
        crosscheck: Bool
    ) {
        self.parsingLoader = parsingLoader
        self.executingLoader = executingLoader
        self.showLimitations = showLimitations
        self.crosscheck = crosscheck
    }

    public func load(
        manifestPath: AbsolutePath,
        manifestToolsVersion: ToolsVersion,
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packageLocation: String,
        packageVersion: (version: Version?, revision: String?)?,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        delegateQueue: DispatchQueue
    ) async throws -> Manifest {
        if crosscheck {
            // When cross-checking, we're doing timings. Pre-load the file
            // to warm the filesystem cache rather than charging it to
            // a particular loader.
            let manifestContents: ByteString
            do {
                manifestContents = try fileSystem.readFileContents(manifestPath)
            } catch {
                throw ManifestParserError.inaccessibleManifest(path: manifestPath, reason: String(describing: error))
            }
            _ = manifestContents
        }

        // Parse the manifest directly with the parsing loader.
        let parsedManifest: Manifest?
        let parsingStartTime = DispatchTime.now()
        let parsingEndTime: DispatchTime
        do {
            let manifest = try parsingLoader.load(
                manifestPath: manifestPath,
                manifestToolsVersion: manifestToolsVersion,
                packageIdentity: packageIdentity,
                packageKind: packageKind,
                packageLocation: packageLocation,
                packageVersion: packageVersion,
                identityResolver: identityResolver,
                dependencyMapper: dependencyMapper,
                fileSystem: fileSystem,
                observabilityScope: observabilityScope,
                delegateQueue: delegateQueue
            )

            // We successfully parsed the manifest. If we aren't
            // cross-checking the results, we're done.
            if !crosscheck {
                return manifest
            }

            parsedManifest = manifest
            parsingEndTime = DispatchTime.now()
        } catch {
            guard case .limitations(let limitations) = error else {
                throw error
            }

            // We hit a limitation of the parsed approach, which can either
            // be a missing feature or something executable in the manifest.
            parsingEndTime = DispatchTime.now()

            if showLimitations {
                print("Manifest parser encountered \(limitations.count) limitations that prevent its use for '\(manifestPath.pathString)'")

                let formatter = DiagnosticsFormatter()
                let filename = manifestPath.pathString
                let locationConverter = SourceLocationConverter(
                    fileName: filename,
                    tree: limitations[0].syntax.root
                )
                for limitation in limitations {
                    let diagLoc = locationConverter.location(
                        for: limitation.syntax.position
                    )
                    let prefix = "\(filename):\(diagLoc.line):\(diagLoc.column):"
                    let message = formatter.formattedMessage(limitation)

                    let source = formatter.annotatedSource(
                        tree: limitation.syntax.root,
                        diags: [limitation.asDiagnostic()]
                    )

                    print(
                        "\(prefix) \(message)\n\(source)"
                    )
                }
            }
            parsedManifest = nil
        }

        // Use the executing loader to process the manifest.
        let executingStartTime = DispatchTime.now()
        let executedManifest = try await executingLoader.load(
            manifestPath: manifestPath,
            manifestToolsVersion: manifestToolsVersion,
            packageIdentity: packageIdentity,
            packageKind: packageKind,
            packageLocation: packageLocation,
            packageVersion: packageVersion,
            identityResolver: identityResolver,
            dependencyMapper: dependencyMapper,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
            delegateQueue: delegateQueue
        )
        let executingEndTime = DispatchTime.now()

        let parsingDuration = parsingStartTime.distance(to: parsingEndTime)
        let executingDuration = executingStartTime.distance(to: executingEndTime)

        // If we have a parsed manifest, it means that we want to
        // cross-check the results. Do so now.
        if let parsedManifest {
            precondition(crosscheck)

            let parsedJSON = try parsedManifest.toJSON()
            let executedJSON = try executedManifest.toJSON()
            guard parsedJSON == executedJSON else {
                print("""
                    Manifest loading cross-check failed for '\(manifestPath.pathString)':
                      - Parsing took \(parsingDuration)
                      - Executing took \(executingDuration)
                    """
                )
                throw ChainedParsingError.manifestMismatch(
                    manifestPath: manifestPath.pathString,
                    parsed: parsedJSON,
                    executed: executedJSON
                )
            }

            print("""
                Manifest loading cross-check succeeded for '\(manifestPath.pathString)':
                  - Parsing took \(parsingDuration)
                  - Executing took \(executingDuration)
                """
            )
            return parsedManifest
        } else {
            print("""
                Manifest loading encountered limitations for '\(manifestPath.pathString)':
                  - Parsing took \(parsingDuration)
                  - Executing took \(executingDuration)
                """
            )
        }

        return executedManifest
    }

    public func resetCache(observabilityScope: Basics.ObservabilityScope) async {
        await parsingLoader.resetCache(observabilityScope: observabilityScope)
        await executingLoader.resetCache(observabilityScope: observabilityScope)
    }

    public func purgeCache(observabilityScope: Basics.ObservabilityScope) async {
        await parsingLoader.purgeCache(observabilityScope: observabilityScope)
        await executingLoader.purgeCache(observabilityScope: observabilityScope)
    }

    enum ChainedParsingError: Error, CustomStringConvertible {
        case manifestMismatch(manifestPath: String, parsed: String, executed: String)

        var description: String {
            switch self {
            case .manifestMismatch(manifestPath: let manifestPath, parsed: let parsed, executed: let expected):
                "The manifest produced by parsing '\(manifestPath)' does not match the one produced by executing: \(parsed) != \(expected)"
            }
        }
    }
}
#endif
