/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

@_exported import enum PackageDescription4.SystemPackageProvider

public class Target: ObjectIdentifierProtocol {
    /// The target kind.
    public enum Kind: String {
        case executable
        case library
        case systemModule = "system-target"
        case test
    }

    /// The name of the target.
    ///
    /// NOTE: This name is not the language-level target (i.e., the importable
    /// name) name in many cases, instead use c99name if you need uniqueness.
    public let name: String

    /// The dependencies of this target.
    public let dependencies: [Target]

    /// The product dependencies of this target.
    public let productDependencies: [(name: String, package: String?)]

    /// The language-level target name.
    public let c99name: String

    /// Suffix that's expected for test targets.
    public static let testModuleNameSuffix = "Tests"

    /// The kind of target.
    public let type: Kind

    /// The sources for the target.
    public let sources: Sources

    fileprivate init(
        name: String,
        type: Kind,
        sources: Sources,
        dependencies: [Target],
        productDependencies: [(name: String, package: String?)] = []
    ) {
        self.name = name
        self.type = type
        self.sources = sources
        self.dependencies = dependencies
        self.productDependencies = productDependencies
        self.c99name = self.name.mangledToC99ExtendedIdentifier()
    }
}

public class SwiftTarget: Target {

    /// The file name of linux main file.
    public static let linuxMainBasename = "LinuxMain.swift"

    /// Create an executable Swift target from linux main test manifest file.
    init(linuxMain: AbsolutePath, name: String, dependencies: [Target]) {
        // Look for the first swift test target and use the same swift version
        // for linux main target. This will need to change if we move to a model
        // where we allow per target swift language version build settings.
        let swiftTestTarget = dependencies.first(where: {
            guard case let target as SwiftTarget = $0 else { return false }
            return target.type == .test
        }).flatMap({ $0 as? SwiftTarget })

        self.swiftVersion = swiftTestTarget?.swiftVersion ?? ToolsVersion.currentToolsVersion.major
        let sources = Sources(paths: [linuxMain], root: linuxMain.parentDirectory)
        super.init(name: name, type: .executable, sources: sources, dependencies: dependencies)
    }

    /// The swift version of this target.
    public let swiftVersion: Int

    public init(
        name: String,
        isTest: Bool = false,
        sources: Sources,
        dependencies: [Target] = [],
        productDependencies: [(name: String, package: String?)] = [],
        swiftVersion: Int
    ) {
        let type: Kind = isTest ? .test : sources.computeModuleType()
        self.swiftVersion = swiftVersion
        super.init(
            name: name,
            type: type,
            sources: sources,
            dependencies: dependencies,
            productDependencies: productDependencies)
    }
}

public class CTarget: Target {

    /// The name of pkgConfig file, if any.
    public let pkgConfig: String?

    /// List of system package providers, if any.
    public let providers: [SystemPackageProvider]?

    /// The package path.
    public var path: AbsolutePath {
        return sources.root
    }

    public init(
        name: String,
        path: AbsolutePath,
        pkgConfig: String? = nil,
        providers: [SystemPackageProvider]? = nil
    ) {
        let sources = Sources(paths: [], root: path)
        self.pkgConfig = pkgConfig
        self.providers = providers
        super.init(name: name, type: .systemModule, sources: sources, dependencies: [])
    }
}

public class ClangTarget: Target {

    public static let defaultPublicHeadersComponent = "include"

    public let includeDir: AbsolutePath

    public init(
        name: String,
        includeDir: AbsolutePath,
        isTest: Bool = false,
        sources: Sources,
        dependencies: [Target] = [],
        productDependencies: [(name: String, package: String?)] = []
    ) {
        assert(includeDir.contains(sources.root), "\(includeDir) should be contained in the source root \(sources.root)")
        let type: Kind = isTest ? .test : sources.computeModuleType()
        self.includeDir = includeDir
        super.init(
            name: name,
            type: type,
            sources: sources,
            dependencies: dependencies,
            productDependencies: productDependencies)
    }
}

extension Target: CustomStringConvertible {
    public var description: String {
        return "<\(Swift.type(of: self)): \(name)>"
    }
}

extension Sources {
    /// Determine target type based on the sources.
    fileprivate func computeModuleType() -> Target.Kind {
        let isLibrary = !relativePaths.contains { path in
            let file = path.basename.lowercased()
            // Look for a main.xxx file avoiding cases like main.xxx.xxx
            return file.hasPrefix("main.") && file.characters.filter({$0 == "."}).count == 1
        }
        return isLibrary ? .library : .executable
    }
}
