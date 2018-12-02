/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

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

    /// The list of platforms that are supported by this target.
    public let platforms: [SupportedPlatform]

    /// Returns the supported platform instance for the given platform.
    public func getSupportedPlatform(for platform: Platform) -> SupportedPlatform? {
        return self.platforms.first(where: { $0.platform == platform })
    }

    /// The build settings assignments of this target.
    public let buildSettings: BuildSettings.AssignmentTable

    fileprivate init(
        name: String,
        platforms: [SupportedPlatform],
        type: Kind,
        sources: Sources,
        dependencies: [Target],
        productDependencies: [(name: String, package: String?)] = [],
        buildSettings: BuildSettings.AssignmentTable
    ) {
        self.name = name
        self.platforms = platforms
        self.type = type
        self.sources = sources
        self.dependencies = dependencies
        self.productDependencies = productDependencies
        self.c99name = self.name.spm_mangledToC99ExtendedIdentifier()
        self.buildSettings = buildSettings
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

        // FIXME: This is not very correct but doesn't matter much in practice.
        // We need to select the latest Swift language version that can
        // satisfy the current tools version but there is not a good way to
        // do that currently.
        self.swiftVersion = swiftTestTarget?.swiftVersion ?? SwiftLanguageVersion(string: String(ToolsVersion.currentToolsVersion.major)) ?? .v4
        let sources = Sources(paths: [linuxMain], root: linuxMain.parentDirectory)

        let platforms: [SupportedPlatform] = swiftTestTarget?.platforms ?? []

        super.init(
            name: name,
            platforms: platforms,
            type: .executable,
            sources: sources,
            dependencies: dependencies,
            buildSettings: .init()

        )
    }

    /// The swift version of this target.
    public let swiftVersion: SwiftLanguageVersion

    public init(
        name: String,
        platforms: [SupportedPlatform] = [],
        isTest: Bool = false,
        sources: Sources,
        dependencies: [Target] = [],
        productDependencies: [(name: String, package: String?)] = [],
        swiftVersion: SwiftLanguageVersion,
        buildSettings: BuildSettings.AssignmentTable = .init()
    ) {
        let type: Kind = isTest ? .test : sources.computeTargetType()
        self.swiftVersion = swiftVersion
        super.init(
            name: name,
            platforms: platforms,
            type: type,
            sources: sources,
            dependencies: dependencies,
            productDependencies: productDependencies,
            buildSettings: buildSettings
        )
    }
}

public class SystemLibraryTarget: Target {

    /// The name of pkgConfig file, if any.
    public let pkgConfig: String?

    /// List of system package providers, if any.
    public let providers: [SystemPackageProviderDescription]?

    /// The package path.
    public var path: AbsolutePath {
        return sources.root
    }

    /// True if this system library should become implicit target
    /// dependency of its dependent packages.
    public let isImplicit: Bool

    public init(
        name: String,
        platforms: [SupportedPlatform] = [],
        path: AbsolutePath,
        isImplicit: Bool = true,
        pkgConfig: String? = nil,
        providers: [SystemPackageProviderDescription]? = nil
    ) {
        let sources = Sources(paths: [], root: path)
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.isImplicit = isImplicit
        super.init(
            name: name,
            platforms: platforms,
            type: .systemModule,
            sources: sources,
            dependencies: [],
            buildSettings: .init()
        )
    }
}

public class ClangTarget: Target {

    /// The default public include directory component.
    public static let defaultPublicHeadersComponent = "include"

    /// The path to include directory.
    public let includeDir: AbsolutePath

    /// True if this is a C++ target.
    public let isCXX: Bool

    /// The C language standard flag.
    public let cLanguageStandard: String?

    /// The C++ language standard flag.
    public let cxxLanguageStandard: String?

    public init(
        name: String,
        platforms: [SupportedPlatform] = [],
        cLanguageStandard: String?,
        cxxLanguageStandard: String?,
        includeDir: AbsolutePath,
        isTest: Bool = false,
        sources: Sources,
        dependencies: [Target] = [],
        productDependencies: [(name: String, package: String?)] = [],
        buildSettings: BuildSettings.AssignmentTable = .init()
    ) {
        assert(includeDir.contains(sources.root), "\(includeDir) should be contained in the source root \(sources.root)")
        let type: Kind = isTest ? .test : sources.computeTargetType()
        self.isCXX = sources.containsCXXFiles
        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard
        self.includeDir = includeDir
        super.init(
            name: name,
            platforms: platforms,
            type: type,
            sources: sources,
            dependencies: dependencies,
            productDependencies: productDependencies,
            buildSettings: buildSettings
        )
    }
}

extension Target: CustomStringConvertible {
    public var description: String {
        return "<\(Swift.type(of: self)): \(name)>"
    }
}

extension Sources {
    /// Determine target type based on the sources.
    fileprivate func computeTargetType() -> Target.Kind {
        let isLibrary = !relativePaths.contains { path in
            let file = path.basename.lowercased()
            // Look for a main.xxx file avoiding cases like main.xxx.xxx
            return file.hasPrefix("main.") && String(file.filter({$0 == "."})).count == 1
        }
        return isLibrary ? .library : .executable
    }
}
