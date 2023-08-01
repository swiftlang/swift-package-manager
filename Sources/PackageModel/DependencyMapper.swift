//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import enum TSCBasic.PathValidationError

public protocol DependencyMapper {
    func mappedDependency(for dependency: PackageDependency, fileSystem: FileSystem) throws -> PackageDependency
    func mappedDependency(packageKind: PackageReference.Kind?, at location: String, nameForTargetDependencyResolutionOnly: String?, requirement: PackageDependency.Registry.Requirement, productFilter: ProductFilter, fileSystem: FileSystem) throws -> PackageDependency
    func mappedDependency(packageKind: PackageReference.Kind?, at location: String, nameForTargetDependencyResolutionOnly: String?, requirement: PackageDependency.SourceControl.Requirement, productFilter: ProductFilter, fileSystem: FileSystem) throws -> PackageDependency
}

public struct DefaultDependencyMapper: DependencyMapper {
    let identityResolver: IdentityResolver

    public init(
        identityResolver: IdentityResolver
    ) {
        self.identityResolver = identityResolver
    }

    public func mappedDependency(for dependency: PackageDependency, fileSystem: FileSystem) throws -> PackageDependency {
        switch dependency {
        case .fileSystem:
            return dependency
        case .registry(let settings):
            return try self.mappedDependency(packageKind: nil, at: settings.identity.description, nameForTargetDependencyResolutionOnly: nil, requirement: .init(settings.requirement), productFilter: settings.productFilter, fileSystem: fileSystem)
        case .sourceControl(let settings):
            var location: String
            let packageKind: PackageReference.Kind
            switch settings.location {
            case .local(let path):
                location = path.pathString
                packageKind = .localSourceControl(path)
            case .remote(let url):
                location = url.absoluteString
                packageKind = .remoteSourceControl(url)
            }
            return try self.mappedDependency(packageKind: packageKind, at: location, nameForTargetDependencyResolutionOnly: settings.nameForTargetDependencyResolutionOnly, requirement: settings.requirement, productFilter: settings.productFilter, fileSystem: fileSystem)
        }
    }

    public func mappedDependency(
        packageKind: PackageReference.Kind?,
        at location: String,
        nameForTargetDependencyResolutionOnly: String?,
        requirement: PackageDependency.SourceControl.Requirement,
        productFilter: ProductFilter,
        fileSystem: FileSystem
    ) throws -> PackageDependency {
        var location = location
        if let packageKind {
            // cleans up variants of path based location
            location = try Self.sanitizeDependencyLocation(fileSystem: fileSystem, packageKind: packageKind, dependencyLocation: location)
        }

        // location mapping (aka mirrors) if any
        location = self.identityResolver.mappedLocation(for: location)
        if PackageIdentity.plain(location).isRegistry {
            // re-mapped to registry
            let identity = PackageIdentity.plain(location)
            return .registry(
                identity: identity,
                requirement: try .init(requirement),
                productFilter: productFilter
            )
        } else if let localPath = try? AbsolutePath(validating: location) {
            // a package in a git location, may be a remote URL or on disk
            // in the future this will check with the registries for the identity of the URL
            let identity = try self.identityResolver.resolveIdentity(for: localPath)
            return .localSourceControl(
                identity: identity,
                nameForTargetDependencyResolutionOnly: nameForTargetDependencyResolutionOnly,
                path: localPath,
                requirement: requirement,
                productFilter: productFilter
            )
        } else {
            let url = SourceControlURL(location)
            // in the future this will check with the registries for the identity of the URL
            let identity = try self.identityResolver.resolveIdentity(for: url)
            return .remoteSourceControl(
                identity: identity,
                nameForTargetDependencyResolutionOnly: nameForTargetDependencyResolutionOnly,
                url: url,
                requirement: requirement,
                productFilter: productFilter
            )
        }
    }

    public func mappedDependency(
        packageKind: PackageReference.Kind?,
        at location: String,
        nameForTargetDependencyResolutionOnly: String?,
        requirement: PackageDependency.Registry.Requirement,
        productFilter: ProductFilter, fileSystem: FileSystem
    ) throws -> PackageDependency {
        return try self.mappedDependency(packageKind: packageKind, at: location, nameForTargetDependencyResolutionOnly: nameForTargetDependencyResolutionOnly, requirement: .init(requirement), productFilter: productFilter, fileSystem: fileSystem)
    }

    private static let filePrefix = "file://"

    /// Parses the URL type of a git repository
    /// e.g. https://github.com/apple/swift returns "https"
    /// e.g. git@github.com:apple/swift returns "git"
    ///
    /// This is *not* a generic URI scheme parser!
    private static func parseScheme(_ location: String) -> String? {
        func prefixOfSplitBy(_ delimiter: String) -> String? {
            let (head, tail) = location.spm_split(around: delimiter)
            if tail == nil {
                //not found
                return nil
            } else {
                //found, return head
                //lowercase the "scheme", as specified by the URI RFC (just in case)
                return head.lowercased()
            }
        }

        for delim in ["://", "@"] {
            if let found = prefixOfSplitBy(delim), !found.contains("/") {
                return found
            }
        }

        return nil
    }

    public static func sanitizeDependencyLocation(fileSystem: FileSystem, packageKind: PackageReference.Kind, dependencyLocation: String) throws -> String {
        if dependencyLocation.hasPrefix("~/") {
            // If the dependency URL starts with '~/', try to expand it.
            return try AbsolutePath(validating: String(dependencyLocation.dropFirst(2)), relativeTo: fileSystem.homeDirectory).pathString
        } else if dependencyLocation.hasPrefix(filePrefix) {
            // FIXME: SwiftPM can't handle file locations with file:// scheme so we need to
            // strip that. We need to design a Location data structure for SwiftPM.
            let location = String(dependencyLocation.dropFirst(filePrefix.count))
            let hostnameComponent = location.prefix(while: { $0 != "/" })
            guard hostnameComponent.isEmpty else {
              if hostnameComponent == ".." {
                  throw DependencyMappingError.invalidFileURL("file:// URLs cannot be relative, did you mean to use '.package(path:)'?")
              }
              throw DependencyMappingError.invalidFileURL("file:// URLs with hostnames are not supported, are you missing a '/'?")
            }
            return try AbsolutePath(validating: location).pathString
        } else if parseScheme(dependencyLocation) == nil {
            // If the URL has no scheme, we treat it as a path (either absolute or relative to the base URL).
            switch packageKind {
            case .root(let packagePath), .fileSystem(let packagePath), .localSourceControl(let packagePath):
                return try AbsolutePath(validating: dependencyLocation, relativeTo: packagePath).pathString
            case .remoteSourceControl, .registry:
                // nothing to "fix"
                return dependencyLocation
            }
        } else {
            // nothing to "fix"
            return dependencyLocation
        }
    }
}

fileprivate extension PackageDependency.Registry.Requirement {
    init(_ requirement: PackageDependency.SourceControl.Requirement) throws {
        switch requirement {
        case .branch, .revision:
            throw DependencyMappingError.invalidMappingToRegistry("invalid mapping of source control to registry, requirement information mismatch: cannot map branch or revision based dependencies to registry.")
        case .exact(let value):
            self = .exact(value)
        case .range(let value):
            self = .range(value)
        }
    }
}

fileprivate extension PackageDependency.SourceControl.Requirement {
    init(_ requirement: PackageDependency.Registry.Requirement) {
        switch requirement {
        case .exact(let value):
            self = .exact(value)
        case .range(let value):
            self = .range(value)
        }
    }
}

private enum DependencyMappingError: Swift.Error, CustomStringConvertible {
    case invalidFileURL(_ message: String)
    case invalidMappingToRegistry(_ message: String)

    var description: String {
        switch self {
        case .invalidFileURL(let message): return message
        case .invalidMappingToRegistry(let message): return message
        }
    }
}
