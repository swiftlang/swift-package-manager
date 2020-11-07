/*
 This source file is part of the Swift.org open source project

 Copyright 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import ArgumentParser
import Foundation
import PackageCollections
import PackageModel
import TSCBasic
import TSCUtility

private enum CollectionsError: Swift.Error {
    case invalidVersionString(String)
    case missingArgument(String)
    case noCollectionMatchingURL(String)
}

extension CollectionsError: CustomStringConvertible {
    var description: String {
        switch self {
        case .invalidVersionString(let versionString):
            return "invalid version string '\(versionString)'"
        case .missingArgument(let argumentName):
            return "missing argument '\(argumentName)'"
        case .noCollectionMatchingURL(let url):
            return "no collection matching URL '\(url)'"
        }
    }
}

struct JSONOptions: ParsableArguments {
    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false
}

struct ProfileOptions: ParsableArguments {
    @Option(name: .long, help: "Profile to use for the given command")
    var profile: String?

    var usedProfile: PackageCollectionsModel.Profile? {
        if let profile = profile {
            return .init(name: profile)
        } else {
            return nil
        }
    }
}

public struct SwiftPackageCollectionsTool: ParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "package-collections",
        _superCommandName: "swift",
        abstract: "Interact with package collections",
        discussion: "SEE ALSO: swift build, swift package, swift run, swift test",
        version: Versioning.currentVersion.completeDisplayString,
        subcommands: [
            Add.self,
            Describe.self,
            DescribeCollection.self,
            List.self,
            ProfileList.self,
            Refresh.self,
            Remove.self,
            Search.self
        ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

    public init() {
    }

    // MARK: Profiles

    struct ProfileList: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List configured profiles")

        @OptionGroup
        var jsonOptions: JSONOptions

        mutating func run() throws {
            let profiles: [PackageCollectionsModel.Profile] = try await { self.collections.listProfiles(callback: $0) }

            if jsonOptions.json {
                try JSONEncoder().print(profiles)
            } else {
                profiles.forEach {
                    print($0)
                }
            }
        }
    }

    // MARK: Collections

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List configured collections")

        @OptionGroup
        var jsonOptions: JSONOptions

        @OptionGroup
        var profileOptions: ProfileOptions

        mutating func run() throws {
            let collections = try await { self.collections.listCollections(identifiers: nil, in: profileOptions.usedProfile, callback: $0) }

            if jsonOptions.json {
                try JSONEncoder().print(collections)
            } else {
                collections.forEach {
                    print("\($0.name) - \($0.source.url)")
                }
            }
        }
    }

    struct Refresh: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Refresh configured collections")

        @OptionGroup
        var profileOptions: ProfileOptions

        mutating func run() throws {
            let collections = try await { self.collections.refreshCollections(in: profileOptions.usedProfile, callback: $0) }
            print("Refreshed \(collections.count) configured package collections.")
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a new collection")

        @Argument(help: "URL of the collection to add")
        var collectionUrl: String?

        @Option(name: .long, help: "Sort order for the added collection")
        var order: Int?

        @OptionGroup
        var profileOptions: ProfileOptions

        mutating func run() throws {
            guard let collectionUrlString = collectionUrl, let collectionUrl = URL(string: collectionUrlString) else {
                throw CollectionsError.missingArgument("collectionUrl")
            }

            let source = PackageCollectionsModel.CollectionSource(url: collectionUrl)
            let collection = try await { self.collections.addCollection(source, order: order, to: profileOptions.usedProfile, callback: $0) }

            print("Added \"\(collection.name)\" to your package collections.")
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove a configured collection")

        @OptionGroup
        var profileOptions: ProfileOptions

        @Argument(help: "URL of the collection to remove")
        var collectionUrl: String?

        mutating func run() throws {
            guard let collectionUrlString = collectionUrl, let collectionUrl = URL(string: collectionUrlString) else {
                throw CollectionsError.missingArgument("collectionUrl")
            }

            let collections = try await { self.collections.listCollections(identifiers: nil, in: profileOptions.usedProfile, callback: $0) }
            let source = PackageCollectionsModel.CollectionSource(url: collectionUrl)

            guard let collection = collections.first(where: { $0.source == source }) else {
                throw CollectionsError.noCollectionMatchingURL(collectionUrlString)
            }

            _ = try await { self.collections.removeCollection(source, from: profileOptions.usedProfile, callback: $0) }
            print("Removed \"\(collection.name)\" from your package collections.")
        }
    }

    struct DescribeCollection: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Get metadata for a configured collection")

        @Argument(help: "URL of the collection to describe")
        var collectionUrl: String?

        @OptionGroup
        var profileOptions: ProfileOptions

        mutating func run() throws {
            guard let collectionUrlString = collectionUrl, let collectionUrl = URL(string: collectionUrlString) else {
                throw CollectionsError.missingArgument("collectionUrl")
            }

            let collections = try await { self.collections.listCollections(identifiers: nil, in: profileOptions.usedProfile, callback: $0) }
            let source = PackageCollectionsModel.CollectionSource(url: collectionUrl)

            guard let collection = collections.first(where: { $0.source == source }) else {
                throw CollectionsError.noCollectionMatchingURL(collectionUrlString)
            }

            let description = optionalRow("Description", collection.description)
            let keywords = optionalRow("Keywords", collection.keywords?.joined(separator: ", "))
            let createdAt = DateFormatter().string(from: collection.createdAt)
            let packages = collection.packages.map { "\($0.repository.url)" }.joined(separator: "\n")

            print("""
                Name: \(collection.name)
                Source: \(collection.source.url)\(description)\(keywords)
                Created At: \(createdAt)
                Packages:
                \(packages)
            """)
        }
    }

    // MARK: Search

    enum SearchMethod: String, EnumerableFlag {
        case keywords
        case module
    }

    struct Search: ParsableCommand {
        static var configuration = CommandConfiguration(abstract: "Search for packages by keywords or module names")

        @OptionGroup
        var jsonOptions: JSONOptions

        @OptionGroup
        var profileOptions: ProfileOptions

        @Flag(help: "Pick the method for searching")
        var searchMethod: SearchMethod

        @Argument(help: "Search query")
        var searchQuery: String?

        mutating func run() throws {
            guard let searchQuery = searchQuery else {
                throw CollectionsError.missingArgument("searchQuery")
            }

            switch searchMethod {
            case .keywords:
                let results = try await { collections.findPackages(searchQuery, collections: nil, profile: profileOptions.usedProfile, callback: $0) }

                results.items.forEach {
                    print("\($0.package.repository.url): \($0.package.description ?? "")")
                }

            case .module:
                let results = try await { collections.findTargets(searchQuery, searchType: .exactMatch, collections: nil, profile: profileOptions.usedProfile, callback: $0) }

                results.items.forEach {
                    $0.packages.forEach {
                        print("\($0.repository.url): \($0.description ?? "")")
                    }
                }
            }
        }
    }

    // MARK: Packages

    struct Describe: ParsableCommand {
        static var configuration = CommandConfiguration(abstract: "Get metadata for a single package")

        @OptionGroup
        var jsonOptions: JSONOptions

        @OptionGroup
        var profileOptions: ProfileOptions

        @Argument(help: "URL of the package to get information for")
        var packageUrl: String?

        @Option(name: .long, help: "Version of the package to get information for")
        var version: String?

        private func printVersion(_ version: PackageCollectionsModel.Package.Version?) -> String? {
            guard let version = version else {
                return nil
            }

            let modules = version.targets.compactMap { $0.moduleName }.joined(separator: ", ")
            let platforms = optionalRow("Verified Platforms", version.verifiedPlatforms?.map { $0.name }.joined(separator: ", "))
            let swiftVersions = optionalRow("Verified Swift Versions", version.verifiedSwiftVersions?.map { $0.rawValue }.joined(separator: ", "))
            let license = optionalRow("License", version.license?.type.description)
            let cves = optionalRow("CVEs", version.cves?.map { $0.identifier }.joined(separator: ", "))

            return """
                \(version.version)
                Package Name: \(version.packageName)
                Modules: \(modules)\(platforms)\(swiftVersions)\(license)\(cves)
            """
        }

        mutating func run() throws {
            guard let packageUrl = packageUrl else {
                throw CollectionsError.missingArgument("packageUrl")
            }

            let identity = PackageReference.computeIdentity(packageURL: packageUrl)
            let reference = PackageReference(identity: identity, path: packageUrl)

            let result = try await { self.collections.getPackageMetadata(reference, profile: profileOptions.usedProfile, callback: $0) }

            if let versionString = version {
                guard let version = TSCUtility.Version(string: versionString), let result = result.package.versions.first(where: { $0.version == version }), let printedResult = printVersion(result) else {
                    throw CollectionsError.invalidVersionString(versionString)
                }

                print("Version: \(printedResult)")
            } else {
                let description = optionalRow("Description", result.package.description)
                let versions = result.package.versions.map { "\($0.version)" }.joined(separator: ", ")
                let watchers = optionalRow("Watchers", result.package.watchersCount?.description)
                let readme = optionalRow("Readme", result.package.readmeURL?.absoluteString)
                let authors = optionalRow("Authors", result.package.authors?.map { $0.username }.joined(separator: ", "))
                let latestVersion = optionalRow("--------------------------------------------------------------\nLatest Version", printVersion(result.package.latestVersion))

                print("""
                    \(description)Available Versions: \(versions)\(watchers)\(readme)\(authors)\(latestVersion)
                """)
            }
        }
    }
}

private func optionalRow(_ title: String, _ contents: String?) -> String {
    if let contents = contents {
        return "\n\(title): \(contents)\n"
    } else {
        return ""
    }
}

private extension JSONEncoder {
    func print<T>(_ value: T) throws where T : Encodable {
        if #available(macOS 10.15, *) {
            self.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        }

        let jsonData = try self.encode(value)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        Swift.print(jsonString)
    }
}

private extension ParsableCommand {
    var collections: PackageCollectionsProtocol {
        fatalError("not implemented")
    }
}
