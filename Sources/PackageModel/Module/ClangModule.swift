//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.AbsolutePath
import struct Basics.StringError
import TSCBasic

@available(*, deprecated, renamed: "ClangModule")
public typealias ClangTarget = ClangModule

/// The C/C++/Objective-C module info for a ClangTarget or mixed-source SwiftTarget
public struct ClangModuleInfo: Equatable, Codable {
    /// The public headers ("include") directory, or `nil` if the target has no public C headers.
    public var includeDir: Basics.AbsolutePath?

    /// The module map type, which determines whether the target vends a custom module map,
    /// a generated module map, or no module map at all.
    public var moduleMapType: ModuleMapType

    /// The headers present in the target (both public and non-public).
    public var headers: [Basics.AbsolutePath]

    /// The C language standard flag.
    public var cLanguageStandard: String?

    /// The C++ language standard flag.
    public var cxxLanguageStandard: String?

    public init(
        includeDir: Basics.AbsolutePath?,
        moduleMapType: ModuleMapType,
        headers: [Basics.AbsolutePath] = [],
        cLanguageStandard: String? = nil,
        cxxLanguageStandard: String? = nil
    ) {
        self.includeDir = includeDir
        self.moduleMapType = moduleMapType
        self.headers = headers
        self.cLanguageStandard = cLanguageStandard
        self.cxxLanguageStandard = cxxLanguageStandard
    }
}

public final class ClangModule: Module {
    /// Description of the module type used in `swift package describe` output. Preserved for backwards compatibility.
    public override class var typeDescription: String { "ClangTarget" }

    /// The default public include directory component.
    public static let defaultPublicHeadersComponent = "include"

    public let clangModuleInfo: ClangModuleInfo

    public var includeDir: Basics.AbsolutePath { self.clangModuleInfo.includeDir! }
    public var moduleMapType: ModuleMapType { self.clangModuleInfo.moduleMapType }
    public var headers: [Basics.AbsolutePath] { self.clangModuleInfo.headers }
    public var cLanguageStandard: String? { self.clangModuleInfo.cLanguageStandard }
    public var cxxLanguageStandard: String? { self.clangModuleInfo.cxxLanguageStandard }

    /// True if this is a C++ target.
    public let isCXX: Bool

    public init(
        name: String,
        potentialBundleName: String? = nil,
        cLanguageStandard: String?,
        cxxLanguageStandard: String?,
        includeDir: Basics.AbsolutePath,
        moduleMapType: ModuleMapType,
        headers: [Basics.AbsolutePath] = [],
        type: Kind,
        path: Basics.AbsolutePath,
        sources: Sources,
        resources: [Resource] = [],
        ignored: [Basics.AbsolutePath] = [],
        others: [Basics.AbsolutePath] = [],
        dependencies: [Module.Dependency] = [],
        buildSettings: BuildSettings.AssignmentTable = .init(),
        buildSettingsDescription: [TargetBuildSettingDescription.Setting] = [],
        usesUnsafeFlags: Bool,
        implicit: Bool
    ) throws {
        guard includeDir.isDescendantOfOrEqual(to: sources.root) else {
            throw StringError("\(includeDir) should be contained in the source root \(sources.root)")
        }
        self.isCXX = sources.containsCXXFiles
        self.clangModuleInfo = ClangModuleInfo(
            includeDir: includeDir,
            moduleMapType: moduleMapType,
            headers: headers,
            cLanguageStandard: cLanguageStandard,
            cxxLanguageStandard: cxxLanguageStandard
        )
        super.init(
            name: name,
            potentialBundleName: potentialBundleName,
            type: type,
            path: path,
            sources: sources,
            resources: resources,
            ignored: ignored,
            others: others,
            dependencies: dependencies,
            packageAccess: false,
            buildSettings: buildSettings,
            buildSettingsDescription: buildSettingsDescription,
            pluginUsages: [],
            usesUnsafeFlags: usesUnsafeFlags,
            implicit: implicit
        )
    }
}
