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

import ArgumentParser
import Basics
import Commands
import CoreCommands
import Foundation
import PackageFingerprint
import PackageModel
import PackageRegistry
import PackageSigning
import Workspace

import struct TSCBasic.SHA256

extension PackageRegistryCommand {
    struct Search: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Search configured package registries."
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @Argument(help: "Search query (free text and/or qualifiers like author:\"Mona\", scope:apple).")
        var query: [String] = []

        @Option(help: "Maximum results to return (1-100).")
        var limit: Int = 20

        @Option(help: "Number of results to skip.")
        var offset: Int = 0

        @Option(help: "Restrict search to a single registry URL.")
        var registry: URL?

        @Flag(help: "Output results as JSON.")
        var json: Bool = false

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let configuration = try PackageRegistryCommand.getRegistriesConfig(
                swiftCommandState,
                global: false
            ).configuration

            let targets = try resolveTargets(configuration: configuration)
            guard !targets.isEmpty else {
                throw ValidationError.unknownRegistry
            }

            let authorizationProvider = try swiftCommandState.getRegistryAuthorizationProvider()
            let registryClient = RegistryClient(
                configuration: configuration,
                fingerprintStorage: .none,
                fingerprintCheckingMode: .strict,
                skipSignatureValidation: false,
                signingEntityStorage: .none,
                signingEntityCheckingMode: .strict,
                authorizationProvider: authorizationProvider,
                delegate: .none,
                checksumAlgorithm: SHA256()
            )

            let queryString = self.query.joined(separator: " ")
            let observabilityScope = swiftCommandState.observabilityScope

            let outcomes = await withTaskGroup(of: RegistryOutcome.self) { group in
                for registry in targets {
                    group.addTask {
                        do {
                            let results = try await registryClient.search(
                                query: queryString,
                                limit: self.limit,
                                offset: self.offset,
                                registry: registry,
                                observabilityScope: observabilityScope
                            )
                            return RegistryOutcome(registry: registry, kind: .success(results))
                        } catch let error as RegistryError {
                            switch error {
                            case .capabilityNotSupported, .registryNotAvailable:
                                return RegistryOutcome(registry: registry, kind: .unsupported)
                            default:
                                return RegistryOutcome(registry: registry, kind: .failed(error))
                            }
                        } catch {
                            return RegistryOutcome(registry: registry, kind: .failed(error))
                        }
                    }
                }

                var collected: [RegistryOutcome] = []
                for await outcome in group {
                    collected.append(outcome)
                }
                return collected
            }

            let unsupported = outcomes.filter { if case .unsupported = $0.kind { return true } else { return false } }
            let failed = outcomes.compactMap { outcome -> (Registry, Error)? in
                if case .failed(let error) = outcome.kind { return (outcome.registry, error) }
                return nil
            }
            let successes = outcomes.compactMap { outcome -> (Registry, RegistryClient.SearchResults)? in
                if case .success(let results) = outcome.kind { return (outcome.registry, results) }
                return nil
            }

            for (registry, error) in failed {
                observabilityScope.emit(
                    warning: "search against registry at '\(registry.url)' failed: \(error.interpolationDescription)"
                )
            }

            if successes.isEmpty {
                if !unsupported.isEmpty && failed.isEmpty {
                    throw StringError("none of the configured registries support search")
                }
                throw StringError("no search results were returned by any configured registry")
            }

            if !unsupported.isEmpty && !self.json {
                let urls = unsupported.map { "'\($0.registry.url)'" }.joined(separator: ", ")
                observabilityScope.emit(
                    warning: "the following registries do not support search and were skipped: \(urls)"
                )
            }

            let multiRegistry = successes.count > 1
            let items = Self.interleavePairs(successes)
            let totalSum = successes.reduce(0) { $0 + $1.1.total }

            if self.json {
                try printJSON(
                    items: items,
                    multiRegistry: multiRegistry,
                    total: totalSum
                )
            } else if items.isEmpty {
                print("No packages matched your query.")
            } else {
                printText(items: items, multiRegistry: multiRegistry)
            }
        }

        private func resolveTargets(configuration: RegistryConfiguration) throws -> [Registry] {
            if let url = self.registry {
                try url.validateRegistryURL(allowHTTP: false)
                return [Registry(url: url, supportsAvailability: true)]
            }

            var seen = Swift.Set<URL>()
            var ordered: [Registry] = []
            if let defaultRegistry = configuration.defaultRegistry, seen.insert(defaultRegistry.url).inserted {
                ordered.append(Registry(url: defaultRegistry.url, supportsAvailability: true))
            }
            for (_, registry) in configuration.scopedRegistries where seen.insert(registry.url).inserted {
                ordered.append(Registry(url: registry.url, supportsAvailability: true))
            }
            return ordered
        }

        static func interleavePairs(
            _ successes: [(Registry, RegistryClient.SearchResults)]
        ) -> [(registry: Registry, result: RegistryClient.SearchResults.Result)] {
            var iterators = successes.map { ($0.0, $0.1.results.makeIterator()) }
            var merged: [(registry: Registry, result: RegistryClient.SearchResults.Result)] = []
            var stillProducing = true
            while stillProducing {
                stillProducing = false
                for index in iterators.indices {
                    if let next = iterators[index].1.next() {
                        merged.append((registry: iterators[index].0, result: next))
                        stillProducing = true
                    }
                }
            }
            return merged
        }

        private func printText(
            items: [(registry: Registry, result: RegistryClient.SearchResults.Result)],
            multiRegistry: Bool
        ) {
            for item in items {
                let summary = item.result.summary ?? ""
                let version = item.result.latestVersion.map { " (v\($0))" } ?? ""
                let suffix = summary.isEmpty ? "" : " - \(summary)"
                let registryAnnotation = multiRegistry ? " [\(item.registry.url)]" : ""
                print("\(item.result.identity)\(suffix)\(version)\(registryAnnotation)")
            }
        }

        private func printJSON(
            items: [(registry: Registry, result: RegistryClient.SearchResults.Result)],
            multiRegistry: Bool,
            total: Int
        ) throws {
            let encoder = JSONEncoder.makeWithDefaults()
            encoder.outputFormatting.insert(.sortedKeys)
            let payload = JSONOutput(
                results: items.map { item in
                    JSONOutput.Result(
                        identity: item.result.identity,
                        summary: item.result.summary,
                        versions: item.result.versions.isEmpty ? nil : item.result.versions,
                        latestVersion: item.result.latestVersion,
                        author: item.result.author,
                        licenseURL: item.result.licenseURL?.absoluteString,
                        url: item.result.url?.absoluteString,
                        registry: multiRegistry ? item.registry.url.absoluteString : nil
                    )
                },
                total: total,
                offset: self.offset,
                limit: self.limit
            )
            let data = try encoder.encode(payload)
            if let string = String(data: data, encoding: .utf8) {
                print(string)
            }
        }

        private struct RegistryOutcome {
            let registry: Registry
            let kind: Kind

            enum Kind {
                case success(RegistryClient.SearchResults)
                case unsupported
                case failed(Error)
            }
        }

        private struct JSONOutput: Encodable {
            let results: [Result]
            let total: Int
            let offset: Int
            let limit: Int

            struct Result: Encodable {
                let identity: String
                let summary: String?
                let versions: [String]?
                let latestVersion: String?
                let author: String?
                let licenseURL: String?
                let url: String?
                let registry: String?
            }
        }
    }
}
