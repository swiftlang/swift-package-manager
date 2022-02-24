/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import Foundation
import PackageModel
import TSCBasic

/// A utility to compute the source/resource files of a target.
public struct TargetSourcesBuilder {
    /// The package identity.
    public let packageIdentity: PackageIdentity

    /// The package kind.
    public let packageKind: PackageReference.Kind

    /// The package path.
    public let packagePath: AbsolutePath

    /// The target for which we're computing source/resource files.
    public let target: TargetDescription

    /// The path of the target.
    public let targetPath: AbsolutePath

    /// The list of declared sources in the package manifest.
    public let declaredSources: [AbsolutePath]?

    /// The default localization.
    public let defaultLocalization: String?

    /// The rules that can be applied to files in the target.
    public let rules: [FileRuleDescription]

    /// The tools version associated with the target's package.
    public let toolsVersion: ToolsVersion

    /// The set of paths that should be excluded from any consideration.
    public let excludedPaths: Set<AbsolutePath>

    /// The set of opaque directories extensions (should not be treated as source)
    private let opaqueDirectoriesExtensions: Set<String>

    /// The file system to operate on.
    private let fileSystem: FileSystem

    /// ObservabilityScope with which to emit diagnostics
    private let observabilityScope: ObservabilityScope

    /// Create a new target builder.
    public init(
        packageIdentity: PackageIdentity,
        packageKind: PackageReference.Kind,
        packagePath: AbsolutePath,
        target: TargetDescription,
        path: AbsolutePath,
        defaultLocalization: String?,
        additionalFileRules: [FileRuleDescription] = [],
        toolsVersion: ToolsVersion = .currentToolsVersion,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) {
        self.packageIdentity = packageIdentity
        self.packageKind = packageKind
        //self.packageLocation = packageLocation
        self.packagePath = packagePath
        self.target = target
        self.defaultLocalization = defaultLocalization
        self.targetPath = path
        // In version 5.4 and earlier, SwiftPM did not support `additionalFileRules` and always implicitly included XCBuild file types.
        let actualAdditionalRules = (toolsVersion <= ToolsVersion.v5_4 ? FileRuleDescription.xcbuildFileTypes : additionalFileRules)
        self.rules = FileRuleDescription.builtinRules + actualAdditionalRules
        self.toolsVersion = toolsVersion
        let excludedPaths = target.exclude.map{ path.appending(RelativePath($0)) }
        self.excludedPaths = Set(excludedPaths)
        self.opaqueDirectoriesExtensions = FileRuleDescription.opaqueDirectoriesExtensions.union(
            additionalFileRules.reduce(into: Set<String>(), { partial, item in
                partial.formUnion(item.fileTypes)
            })
        )
        self.fileSystem = fileSystem

        self.observabilityScope = observabilityScope.makeChildScope(description: "TargetSourcesBuilder") {
            var metadata = ObservabilityMetadata.packageMetadata(identity: packageIdentity, kind: packageKind)
            metadata.targetName = target.name
            return metadata
        }

        let declaredSources = target.sources?.map{ path.appending(RelativePath($0)) }
        if let declaredSources = declaredSources {
            // Diagnose duplicate entries.
            let duplicates = declaredSources.spm_findDuplicateElements()
            if !duplicates.isEmpty {
                for duplicate in duplicates {
                    self.observabilityScope.emit(warning: "found duplicate sources declaration in the package manifest: \(duplicate.map{ $0.pathString }[0])")
                }
            }
        }
        self.declaredSources = declaredSources?.spm_uniqueElements()

        self.excludedPaths.forEach { exclude in
            if let message = validTargetPath(at: exclude), self.packageKind.emitAuthorWarnings {
                let warning = "Invalid Exclude '\(exclude)': \(message)."
                self.observabilityScope.emit(warning: warning)
            }
        }

        self.declaredSources?.forEach { source in
            if let message = validTargetPath(at: source) {
                let warning = "Invalid Source '\(source)': \(message)."
                self.observabilityScope.emit(warning: warning)
            }
        }

      #if DEBUG
        validateRules(self.rules)
      #endif
    }

    @discardableResult
    private func validTargetPath(at: AbsolutePath) -> Error? {
        // Check if paths that are enumerated in targets: [] exist
        guard self.fileSystem.exists(at) else {
            return StringError("File not found")
        }

        // Excludes, Sources, and Resources should be found at the root of the package and or
        // its subdirectories
        guard at.pathString.hasPrefix(self.packagePath.pathString) else {
            return StringError("File must be within the package directory structure")
        }

        return nil
    }

    /// Emits an error in debug mode if we have conflicting rules for any file type.
    private func validateRules(_ rules: [FileRuleDescription]) {
        var extensionMap: [String: FileRuleDescription] = [:]
        for rule in rules {
            for ext in rule.fileTypes {
                if let existingRule = extensionMap[ext] {
                    self.observabilityScope.emit(error: "conflicting rules \(rule) and \(existingRule) for extension \(ext)")
                }
                extensionMap[ext] = rule
            }
        }
    }

    /// Run the builder to produce the sources of the target.
    public func run() throws -> (sources: Sources, resources: [Resource], headers: [AbsolutePath], ignored: [AbsolutePath], others: [AbsolutePath]) {
        let contents = self.computeContents()
        var pathToRule: [AbsolutePath: FileRuleDescription.Rule] = [:]

        for path in contents {
            pathToRule[path] = self.computeRule(for: path)
        }

        let headers = pathToRule.lazy.filter { $0.value == .header }.map { $0.key }.sorted()
        let compilePaths = pathToRule.lazy.filter { $0.value == .compile }.map { $0.key }
        let sources = Sources(paths: Array(compilePaths), root: targetPath)
        let resources: [Resource] = pathToRule.compactMap { resource(for: $0.key, with: $0.value) }
        let ignored = pathToRule.filter { $0.value == .ignored }.map { $0.key }
        let others = pathToRule.filter { $0.value == .none }.map { $0.key }

        diagnoseConflictingResources(in: resources)
        diagnoseCopyConflictsWithLocalizationDirectories(in: resources)
        diagnoseLocalizedAndUnlocalizedVariants(in: resources)
        diagnoseMissingDevelopmentRegionResource(in: resources)
        diagnoseInfoPlistConflicts(in: resources)
        diagnoseInvalidResource(in: target.resources)

        // It's an error to contain mixed language source files.
        if sources.containsMixedLanguage {
            throw Target.Error.mixedSources(targetPath)
        }

        return (sources, resources, headers, ignored, others)
    }

    /// Compute the rule for the given path.
    private func computeRule(for path: AbsolutePath) -> FileRuleDescription.Rule {
        var matchedRule: FileRuleDescription.Rule = .none

        // First match any resources explicitly declared in the manifest file.
        for declaredResource in target.resources {
            let resourcePath = self.targetPath.appending(RelativePath(declaredResource.path))
            if path.isDescendantOfOrEqual(to: resourcePath) {
                if matchedRule != .none {
                    self.observabilityScope.emit(error: "duplicate resource rule '\(declaredResource.rule)' found for file at '\(path)'")
                }
                matchedRule = .init(declaredResource.rule)
            }
        }

        // Match any sources explicitly declared in the manifest file.
        if let declaredSources = self.declaredSources {
            for sourcePath in declaredSources {
                if path.isDescendantOfOrEqual(to: sourcePath) {
                    if matchedRule != .none {
                        self.observabilityScope.emit(error: "duplicate rule found for file at '\(path)'")
                    }

                    // Check for header files as they're allowed to be mixed with sources.
                    if let ext = path.extension,
                      FileRuleDescription.header.fileTypes.contains(ext) {
                        matchedRule = .header
                    } else if toolsVersion >= .v5_3 {
                        matchedRule = .compile
                    } else if let ext = path.extension,
                      SupportedLanguageExtension.validExtensions(toolsVersion: toolsVersion).contains(ext) {
                        matchedRule = .compile
                    }
                    // The source file might have been declared twice so
                    // exit on first match.
                    // FIXME: We should emitting warnings for duplicate// declarations.
                    break
                }
            }
        }

        // We haven't found a rule using that's explicitly declared in the manifest
        // so try doing an automatic match.
        if matchedRule == .none {
            let effectiveRules: [FileRuleDescription] = {
                // Don't automatically match compile rules if target's sources are
                // explicitly declared in the package manifest.
                if target.sources != nil {
                    return self.rules.filter { $0.rule != .compile }
                }
                return self.rules
            }()

            if let needle = effectiveRules.first(where: { $0.match(path: path, toolsVersion: toolsVersion) }) {
                matchedRule = needle.rule
            } else if path.parentDirectory.extension == Resource.localizationDirectoryExtension {
                matchedRule = .processResource(localization: .none)
            }
        }

        return matchedRule
    }

    /// Returns the `Resource` file associated with a file and a particular rule, if there is one.
    private func resource(for path: AbsolutePath, with rule: FileRuleDescription.Rule) -> Resource? {
        switch rule {
        case .compile, .header, .none, .modulemap, .ignored:
            return nil
        case .processResource:
            let implicitLocalization: String? = {
                if path.parentDirectory.extension == Resource.localizationDirectoryExtension {
                    return path.parentDirectory.basenameWithoutExt
                } else {
                    return nil
                }
            }()

            let explicitLocalization: String? = {
                switch rule  {
                case .processResource(localization: .default):
                    return defaultLocalization ?? "en"
                case .processResource(localization: .base):
                    return "Base"
                default:
                    return .none
                }
            }()

            // If a resource is both inside a localization directory and has an explicit localization, it's ambiguous.
            guard implicitLocalization == nil || explicitLocalization == nil else {
                let relativePath = path.relative(to: targetPath)
                self.observabilityScope.emit(.localizationAmbiguity(path: relativePath, targetName: target.name))
                return nil
            }

            return Resource(rule: .process(localization: implicitLocalization ?? explicitLocalization), path: path)
        case .copy:
            return Resource(rule: .copy, path: path)
        }
    }

    private func diagnoseConflictingResources(in resources: [Resource]) {
        let duplicateResources = resources.spm_findDuplicateElements(by: \.destination)
        for resources in duplicateResources {
            self.observabilityScope.emit(.conflictingResource(path: resources[0].destination, targetName: target.name))

            for resource in resources {
                let relativePath = resource.path.relative(to: targetPath)
                self.observabilityScope.emit(.fileReference(path: relativePath))
            }
        }
    }

    private func diagnoseCopyConflictsWithLocalizationDirectories(in resources: [Resource]) {
        let localizationDirectories = Set(resources
            .lazy
            .compactMap({ $0.localization })
            .map({ "\($0).\(Resource.localizationDirectoryExtension)" }))

        for resource in resources where resource.rule == .copy {
            if localizationDirectories.contains(resource.path.basename.lowercased()) {
                let relativePath = resource.path.relative(to: targetPath)
                self.observabilityScope.emit(.copyConflictWithLocalizationDirectory(path: relativePath, targetName: target.name))
            }
        }
    }

    private func diagnoseLocalizedAndUnlocalizedVariants(in resources: [Resource]) {
        let resourcesByBasename = Dictionary(grouping: resources, by: { $0.path.basename })
        for (basename, resources) in resourcesByBasename {
            let hasLocalizations = resources.contains(where: { $0.localization != nil })
            let hasUnlocalized = resources.contains(where: { $0.localization == nil })
            if hasLocalizations && hasUnlocalized {
                self.observabilityScope.emit(.localizedAndUnlocalizedVariants(resource: basename, targetName: target.name))
            }
        }
    }

    private func diagnoseMissingDevelopmentRegionResource(in resources: [Resource]) {
        // We can't diagnose anything here without a default localization set.
        guard let defaultLocalization = self.defaultLocalization else {
            return
        }

        let localizedResources = resources.lazy.filter({ $0.localization != nil && $0.localization != "Base" })
        let resourcesByBasename = Dictionary(grouping: localizedResources, by: { $0.path.basename })
        for (basename, resources) in resourcesByBasename {
            if !resources.contains(where: { $0.localization == defaultLocalization }) {
                self.observabilityScope.emit(.missingDefaultLocalizationResource(
                    resource: basename,
                    targetName: target.name,
                    defaultLocalization: defaultLocalization))
            }
        }
    }

    private func diagnoseInfoPlistConflicts(in resources: [Resource]) {
        for resource in resources {
            if resource.destination == RelativePath("Info.plist") {
                self.observabilityScope.emit(.infoPlistResourceConflict(
                    path: resource.path.relative(to: targetPath),
                    targetName: target.name))
            }
        }
    }

    private func diagnoseInvalidResource(in resources: [TargetDescription.Resource]) {
        resources.forEach { resource in
            let resourcePath = self.targetPath.appending(RelativePath(resource.path))
            if let message = validTargetPath(at: resourcePath), self.packageKind.emitAuthorWarnings {
                let warning = "Invalid Resource '\(resource.path)': \(message)."
                self.observabilityScope.emit(warning: warning)
            }
        }
    }

    /// Returns true if the given path is a declared source.
    func isDeclaredSource(_ path: AbsolutePath) -> Bool {
        return path == targetPath || declaredSources?.contains(path) == true
    }

    /// Compute the contents of the files in a target.
    ///
    /// This avoids recursing into certain directories like exclude or the
    /// ones that should be copied as-is.
    public func computeContents() -> [AbsolutePath] {
        var contents: [AbsolutePath] = []
        var queue: [AbsolutePath] = [targetPath]

        // Ignore xcodeproj and playground directories.
        var ignoredDirectoryExtensions = ["xcodeproj", "playground", "xcworkspace"]

        // Ignore localization directories if not supported.
        if toolsVersion < .v5_3 {
            ignoredDirectoryExtensions.append(Resource.localizationDirectoryExtension)
        }

        while let path = queue.popLast() {
            // Ignore dot files.
            if path.basename.hasPrefix(".") { continue }

            if let ext = path.extension, ignoredDirectoryExtensions.contains(ext) {
                continue
            }

            // Ignore manifest files.
            if path.parentDirectory == self.packagePath {
                if path.basename == Manifest.filename { continue }
                if path.basename == "Package.resolved" { continue }

                // Ignore version-specific manifest files.
                if path.basename.hasPrefix(Manifest.basename + "@") && path.extension == "swift" {
                    continue
                }
            }

            // Ignore if this is an excluded path.
            if self.excludedPaths.contains(path) { continue }

            if self.fileSystem.isSymlink(path) && !self.fileSystem.exists(path, followSymlink: true) {
                self.observabilityScope.emit(.brokenSymlink(path))
                continue
            }

            // Consider non-directories as source files.
            if !self.fileSystem.isDirectory(path) {
                contents.append(path)
                continue
            }

            // At this point, path can only be a directory.
            //
            // Starting tools version with resources, treat directories of known extension as resources
            // ie, do not include their content, and instead treat the directory itself as the content
            if toolsVersion >= .v5_6 {
                if let directoryExtension = path.extension,
                   self.opaqueDirectoriesExtensions.contains(directoryExtension),
                   directoryExtension != Resource.localizationDirectoryExtension,
                   !isDeclaredSource(path)
                {
                    contents.append(path)
                    continue
                }
            } else if toolsVersion >= .v5_3 {
                // maintain the broken behavior prior to fixing it in 5.6
                // see rdar://82933763
                if let directoryExtension = path.extension,
                   directoryExtension != Resource.localizationDirectoryExtension,
                   !isDeclaredSource(path)
                {
                    contents.append(path)
                    continue
                }
            }

            // Check if the directory is marked to be copied.
            let directoryMarkedToBeCopied = target.resources.contains{ resource in
                let resourcePath = self.targetPath.appending(RelativePath(resource.path))
                if resource.rule == .copy && resourcePath == path {
                    return true
                }
                return false
            }

            // If the directory is marked to be copied, don't look inside it.
            if directoryMarkedToBeCopied {
                contents.append(path)
                continue
            }

            // We found a directory inside a localization directory, which is forbidden.
            if path.parentDirectory.extension == Resource.localizationDirectoryExtension {
                let relativePath = path.parentDirectory.relative(to: targetPath)
                self.observabilityScope.emit(.localizationDirectoryContainsSubDirectories(
                    localizationDirectory: relativePath,
                    targetName: target.name))
                continue
            }

            // Otherwise, add its content to the queue.
            let dirContents = self.observabilityScope.trap {
                try self.fileSystem.getDirectoryContents(path).map({ path.appending(component: $0) })
            }
            queue += dirContents ?? []
        }

        return contents
    }
}

/// Describes a rule for including a source or resource file in a target.
public struct FileRuleDescription {
    /// A rule semantically describes a file/directory in a target.
    ///
    /// It is up to the build system to translate a rule into a build command.
    public enum Rule: Equatable {
        /// The compile rule for `sources` in a package.
        case compile

        /// Process resource file rule for any type of platform-specific processing.
        ///
        /// This defaults to copy if there's no specialized behavior.
        case processResource(localization: TargetDescription.Resource.Localization?)

        /// The copy rule.
        case copy

        /// The modulemap rule.
        case modulemap

        /// A header file.
        case header

        /// Indicates that the file should be treated as ignored, without causing an unhandled-file warning.
        case ignored

        /// Sentinal to indicate that no rule was chosen for a given file.
        case none
    }

    /// The rule associated with this description.
    public let rule: Rule

    /// The tools version supported by this rule.
    public let toolsVersion: ToolsVersion

    /// The list of file extensions support by this rule.
    ///
    /// No two rule can have the same file extension.
    public let fileTypes: Set<String>

    public init(rule: Rule, toolsVersion: ToolsVersion, fileTypes: Set<String>) {
        self.rule = rule
        self.toolsVersion = toolsVersion
        self.fileTypes = fileTypes
    }

    /// Match the given path to the rule.
    public func match(path: AbsolutePath, toolsVersion: ToolsVersion) -> Bool {
        if toolsVersion < self.toolsVersion {
            return false
        }

        if let ext = path.extension {
            return self.fileTypes.contains(ext)
        }
        return false
    }

    /// The swift compiler rule.
    public static let swift: FileRuleDescription = {
        .init(
            rule: .compile,
            toolsVersion: .minimumRequired,
            fileTypes: ["swift"]
        )
    }()

    /// The clang compiler rule.
    public static let clang: FileRuleDescription = {
        .init(
            rule: .compile,
            toolsVersion: .minimumRequired,
            fileTypes: ["c", "m", "mm", "cc", "cpp", "cxx"]
        )
    }()

    /// The rule for compiling asm files.
    public static let asm: FileRuleDescription = {
        .init(
            rule: .compile,
            toolsVersion: .v5,
            fileTypes: ["s", "S"]
        )
    }()

    /// The rule for detecting modulemap files.
    public static let modulemap: FileRuleDescription = {
        .init(
            rule: .modulemap,
            toolsVersion: .minimumRequired,
            fileTypes: ["modulemap"]
        )
    }()

    /// The rule for detecting header files.
    public static let header: FileRuleDescription = {
        .init(
            rule: .header,
            toolsVersion: .minimumRequired,
            fileTypes: ["h", "hh", "hpp", "h++", "hp", "hxx", "H", "ipp", "def"]
        )
    }()

    /// File types related to the interface builder and storyboards.
    public static let xib: FileRuleDescription = {
        .init(
            rule: .processResource(localization: .none),
            toolsVersion: .v5_3,
            fileTypes: ["nib", "xib", "storyboard"]
        )
    }()

    /// File types related to the asset catalog.
    public static let assetCatalog: FileRuleDescription = {
        .init(
            rule: .processResource(localization: .none),
            toolsVersion: .v5_3,
            fileTypes: ["xcassets"]
        )
    }()

    /// File types related to the CoreData.
    public static let coredata: FileRuleDescription = {
        .init(
            rule: .processResource(localization: .none),
            toolsVersion: .v5_3,
            fileTypes: ["xcdatamodeld", "xcdatamodel", "xcmappingmodel"]
        )
    }()

    /// File types related to Metal.
    public static let metal: FileRuleDescription = {
        .init(
            rule: .processResource(localization: .none),
            toolsVersion: .v5_3,
            fileTypes: ["metal"]
        )
    }()

    /// File rule to ignore .docc (in the SwiftPM build system).
    public static let docc: FileRuleDescription = {
        .init(
            rule: .ignored,
            toolsVersion: .v5_5,
            fileTypes: ["docc"]
        )
    }()

    /// List of all the builtin rules.
    public static let builtinRules: [FileRuleDescription] = [
        swift,
        clang,
        asm,
        modulemap,
        header,
    ]

    /// List of file types that requires the Xcode build system.
    public static let xcbuildFileTypes: [FileRuleDescription] = [
        xib,
        assetCatalog,
        coredata,
        metal,
    ]

    /// List of file types that apply just to the SwiftPM build system.
    public static let swiftpmFileTypes: [FileRuleDescription] = [
        docc,
    ]

    /// List of file directory extensions that should be treated as opaque, non source, directories.
    public static var opaqueDirectoriesExtensions: Set<String> {
        let types = Self.xcbuildFileTypes + Self.swiftpmFileTypes
        return types.reduce(into: Set<String>(), { partial, item in
            partial.formUnion(item.fileTypes)
        })
    }
}

extension FileRuleDescription.Rule {
    init(_ seed: TargetDescription.Resource.Rule)  {
        switch seed {
        case .process(let localization):
            self = .processResource(localization: localization)
        case .copy:
            self = .copy
        }
    }
}

extension Resource {
    var localization: String? {
        switch self.rule {
        case .process(let localization):
            return localization
        default:
            return .none
        }
    }
}

extension Basics.Diagnostic {
    static func symlinkInSources(symlink: RelativePath, targetName: String) -> Self {
        .warning("ignoring symlink at '\(symlink)' in target '\(targetName)'")
    }

    static func localizationDirectoryContainsSubDirectories(
        localizationDirectory: RelativePath,
        targetName: String
    ) -> Self {
        .error("localization directory '\(localizationDirectory)' in target '\(targetName)' contains sub-directories, which is forbidden")
    }
}

extension ObservabilityMetadata {
    public var targetName: String? {
        get {
            self[TargetNameKey.self]
        }
        set {
            self[TargetNameKey.self] = newValue
        }
    }

    enum TargetNameKey: Key {
        typealias Value = String
    }
}

extension PackageReference.Kind {
    fileprivate var emitAuthorWarnings: Bool {
        switch self {
        case .remoteSourceControl, .registry:
            return false
        default:
            return true
        }
    }
}
