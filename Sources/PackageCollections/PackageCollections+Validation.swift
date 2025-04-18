//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageCollectionsModel
import PackageModel

import struct TSCUtility.Version

// MARK: - Model validations

extension Model.CollectionSource {
    func validate(fileSystem: FileSystem) -> [ValidationMessage]? {
        var messages: [ValidationMessage]?
        let appendMessage = { (message: ValidationMessage) in
            if messages == nil {
                messages = .init()
            }
            messages?.append(message)
        }

        let allowedSchemes = Set(["https", "file"])

        switch self.type {
        case .json:
            let scheme = url.scheme?.lowercased() ?? ""
            if !allowedSchemes.contains(scheme) {
                appendMessage(.error("Scheme (\"\(scheme)\") not allowed: \(url.absoluteString). Must be one of \(allowedSchemes)."))
            } else if scheme == "file" {
                let absolutePath = self.absolutePath

                if absolutePath == nil {
                    appendMessage(.error("Invalid file path: \(self.url.path). It must be an absolute file system path."))
                } else if let absolutePath, !fileSystem.exists(absolutePath) {
                    appendMessage(.error("\(self.url.path) is either a non-local path or the file does not exist."))
                }
            }
        }

        return messages
    }
}

// MARK: - JSON model validations

extension PackageCollectionModel.V1 {
    public struct Validator {
        public let configuration: Configuration

        public init(configuration: Configuration = .init()) {
            self.configuration = configuration
        }

        public func validate(collection: Collection) -> [ValidationMessage]? {
            var messages = [ValidationMessage]()

            let packages = collection.packages
            // Stop validating if collection doesn't pass basic checks
            if packages.isEmpty {
                messages.append(.error("A collection must contain at least one package.", property: "packages"))
            } else if packages.count > self.configuration.maximumPackageCount {
                messages.append(.warning("The collection has (\(packages.count)) packages, which is more than the recommended maximum (\(self.configuration.maximumPackageCount)) and extra data might be ignored.", property: "packages"))
            } else {
                packages.forEach { self.validate(package: $0, messages: &messages) }
            }

            guard messages.isEmpty else {
                return messages
            }

            return nil
        }

        // TODO: validate package url?
        private func validate(package: Collection.Package, messages: inout [ValidationMessage]) {
            let packageID = "\(PackageIdentity(url: SourceControlURL(package.url)).description) (\(package.url.absoluteString))"

            guard !package.versions.isEmpty else {
                messages.append(.error("Package \(packageID) does not have any versions.", property: "package.versions"))
                return
            }

            // Check for duplicate versions
            let nonUniqueVersions = Dictionary(grouping: package.versions, by: { $0.version }).filter { $1.count > 1 }.keys
            if !nonUniqueVersions.isEmpty {
                messages.append(.error("Duplicate version(s) found in package \(packageID): \(nonUniqueVersions).", property: "package.versions"))
            }

            var nonSemanticVersions = [String]()
            let semanticVersions: [TSCUtility.Version] = package.versions.compactMap {
                let semver = TSCUtility.Version(tag: $0.version)
                if semver == nil {
                    nonSemanticVersions.append($0.version)
                }
                return semver
            }

            guard nonSemanticVersions.isEmpty else {
                messages.append(.error("Non semantic version(s) found in package \(packageID): \(nonSemanticVersions).", property: "package.versions"))
                // The next part of validation requires sorting the semvers. Cannot continue if non-semver.
                return
            }

            let sortedVersions = semanticVersions.sorted(by: >)

            var currentMajor: Int?
            var majorCount = 0
            var minorCount = 0
            for version in sortedVersions {
                if version.major != currentMajor {
                    currentMajor = version.major
                    majorCount += 1
                    minorCount = 0
                }

                guard majorCount <= self.configuration.maximumMajorVersionCount else {
                    messages.append(.warning("Package \(packageID) includes too many major versions. Only \(self.configuration.maximumMajorVersionCount) is allowed and extra data might be ignored.", property: "package.versions"))
                    break
                }
                guard minorCount < self.configuration.maximumMinorVersionCount else {
                    // !-safe currentMajor cannot be nil at this point
                    messages.append(.warning("Package \(packageID) includes too many minor versions for major version \(currentMajor!). Only \(self.configuration.maximumMinorVersionCount) is allowed and extra data might be ignored.", property: "package.versions"))
                    break
                }

                minorCount += 1
            }

            package.versions.forEach { version in
                guard !version.manifests.isEmpty else {
                    messages.append(.error("Package \(packageID) version \(version.version) does not have any manifests.", property: "version.manifest"))
                    return
                }
                guard version.manifests[version.defaultToolsVersion] != nil else {
                    messages.append(.error("Package \(packageID) version \(version.version) is missing the default manifest (tools version: \(version.defaultToolsVersion))", property: "version.manifest"))
                    return
                }

                version.manifests.forEach { toolsVersion, manifest in
                    if toolsVersion != manifest.toolsVersion {
                        messages.append(.error("Package \(packageID) manifest tools version \(manifest.toolsVersion) does not match \(toolsVersion)", property: "version.manifest"))
                    }

                    if manifest.products.isEmpty {
                        messages.append(.error("Package \(packageID) version \(version.version) tools-version \(toolsVersion) does not contain any products.", property: "version.manifest.products"))
                    }
                    manifest.products.forEach { product in
                        if product.targets.isEmpty {
                            messages.append(.error("Product \(product.name) of package \(packageID) version \(version.version) tools-version \(toolsVersion) does not contain any targets.", property: "product.targets"))
                        }
                    }

                    if manifest.targets.isEmpty {
                        messages.append(.error("Package \(packageID) version \(version.version) tools-version \(toolsVersion) does not contain any targets.", property: "version.manifest.targets"))
                    }
                }
            }
        }

        public struct Configuration {
            public var maximumPackageCount: Int
            public var maximumMajorVersionCount: Int
            public var maximumMinorVersionCount: Int

            public init(maximumPackageCount: Int? = nil,
                        maximumMajorVersionCount: Int? = nil,
                        maximumMinorVersionCount: Int? = nil) {
                // TODO: where should we read defaults from?
                self.maximumPackageCount = maximumPackageCount ?? 50
                self.maximumMajorVersionCount = maximumMajorVersionCount ?? 2
                self.maximumMinorVersionCount = maximumMinorVersionCount ?? 3
            }
        }
    }
}

// MARK: - ValidationMessage and ValidationError

public struct ValidationMessage: Equatable, CustomStringConvertible {
    public let message: String
    public let level: Level
    public let property: String?

    private init(_ message: String, level: Level, property: String? = nil) {
        self.message = message
        self.level = level
        self.property = property
    }

    static func error(_ message: String, property: String? = nil) -> ValidationMessage {
        .init(message, level: .error, property: property)
    }

    static func warning(_ message: String, property: String? = nil) -> ValidationMessage {
        .init(message, level: .warning, property: property)
    }

    public enum Level: String, Equatable {
        case warning
        case error
    }

    public var description: String {
        "[\(self.level)] \(self.property.map { "\($0): " } ?? "")\(self.message)"
    }
}

extension Array where Element == ValidationMessage {
    func errors(include levels: Set<ValidationMessage.Level> = [.error]) -> [ValidationError]? {
        let errors = self.filter { levels.contains($0.level) }

        guard !errors.isEmpty else { return nil }

        return errors.map {
            if let property = $0.property {
                return ValidationError.property(name: property, message: $0.message)
            } else {
                return ValidationError.other(message: $0.message)
            }
        }
    }
}

public enum ValidationError: Error, Equatable, CustomStringConvertible {
    case property(name: String, message: String)
    case other(message: String)
    
    public var message: String {
        switch self {
        case .property(_, let message):
            return message
        case .other(let message):
            return message
        }
    }

    public var description: String {
        switch self {
        case .property(let name, let message):
            return "\(name): \(message)"
        case .other(let message):
            return message
        }
    }
}
