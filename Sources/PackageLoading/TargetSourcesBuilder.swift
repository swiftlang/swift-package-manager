/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import TSCBasic
import PackageModel
import TSCUtility

/// An utility to compute the source/resource files of a target.
public struct TargetSourcesBuilder {
    /// The target for which we're computing source/resource files.
    public let target: TargetDescription

    /// The engine for emitting diagnostics.
    let diags: DiagnosticsEngine

    /// The name of the package.
    public let packageName: String

    /// The path of the package.
    public let packagePath: AbsolutePath

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

    /// The file system to operate on.
    public let fs: FileSystem

    /// Create a new target builder.
    public init(
        packageName: String,
        packagePath: AbsolutePath,
        target: TargetDescription,
        path: AbsolutePath,
        defaultLocalization: String?,
        additionalFileRules: [FileRuleDescription] = [],
        toolsVersion: ToolsVersion = .currentToolsVersion,
        fs: FileSystem = localFileSystem,
        diags: DiagnosticsEngine
    ) {
        self.packageName = packageName
        self.packagePath = packagePath
        self.target = target
        self.defaultLocalization = defaultLocalization
        self.diags = diags
        self.targetPath = path
        self.rules = FileRuleDescription.builtinRules
        self.toolsVersion = toolsVersion
        self.fs = fs
        let excludedPaths = target.exclude.map{ path.appending(RelativePath($0)) }
        self.excludedPaths = Set(excludedPaths)

        let declaredSources = target.sources?.map{ path.appending(RelativePath($0)) }
        if let declaredSources = declaredSources {
            // Diagnose duplicate entries.
            let duplicates = declaredSources.spm_findDuplicateElements()
            if !duplicates.isEmpty {
                for duplicate in duplicates {
                    diags.emit(warning: "found duplicate sources declaration in the package manifest: \(duplicate.map{ $0.pathString }[0])")
                }
            }
        }
        self.declaredSources = declaredSources?.spm_uniqueElements()

      #if DEBUG
        validateRules(self.rules)
      #endif
    }

    /// Emits an error in debug mode if we have conflicting rules for any file type.
    private func validateRules(_ rules: [FileRuleDescription]) {
        var extensionMap: [String: FileRuleDescription] = [:]
        for rule in rules {
            for ext in rule.fileTypes {
                if let existingRule = extensionMap[ext] {
                    diags.emit(.error("conflicting rules \(rule) and \(existingRule) for extension \(ext)"))
                }
                extensionMap[ext] = rule
            }
        }
    }

    /// Run the builder to produce the sources of the target.
    public func run() throws -> (sources: Sources, resources: [Resource], headers: [AbsolutePath]) {
        let contents = computeContents()
        var pathToRule: [AbsolutePath: Rule] = [:]

        for path in contents {
            pathToRule[path] = findRule(for: path)
        }

        // Emit an error if we found files without a matching rule in
        // tools version >= v5_3. This will be activated once resources
        // support is complete.
        if toolsVersion >= .v5_3 {
            let filesWithNoRules = pathToRule.filter { $0.value.rule == .none }
            if !filesWithNoRules.isEmpty {
                var warning = "found \(filesWithNoRules.count) file(s) which are unhandled; explicitly declare them as resources or exclude from the target\n"
                for (file, _) in filesWithNoRules {
                    warning += "    " + file.pathString + "\n"
                }
                diags.emit(.warning(warning))
            }
        }

        let headers = pathToRule.lazy.filter { $0.value.rule == .header }.map { $0.key }.sorted()
        let compilePaths = pathToRule.lazy.filter { $0.value.rule == .compile }.map { $0.key }
        let sources = Sources(paths: Array(compilePaths), root: targetPath)
        let resources: [Resource] = pathToRule.compactMap { resource(for: $0.key, with: $0.value) }

        diagnoseConflictingResources(in: resources)
        diagnoseCopyConflictsWithLocalizationDirectories(in: resources)
        diagnoseLocalizedAndUnlocalizedVariants(in: resources)
        diagnoseMissingDevelopmentRegionResource(in: resources)
        diagnoseInfoPlistConflicts(in: resources)

        // It's an error to contain mixed language source files.
        if sources.containsMixedLanguage {
            throw Target.Error.mixedSources(targetPath)
        }

        return (sources, resources, headers)
    }

    private struct Rule {
        let rule: FileRuleDescription.Rule
        let localization: TargetDescription.Resource.Localization?
    }

    /// Find the rule for the given path.
    private func findRule(for path: AbsolutePath) -> Rule {
        var matchedRule: Rule = Rule(rule: .none, localization: nil)

        // First match any resources explicitly declared in the manifest file.
        for declaredResource in target.resources {
            let resourcePath = self.targetPath.appending(RelativePath(declaredResource.path))
            if path.contains(resourcePath) {
                if matchedRule.rule != .none {
                    diags.emit(.error("duplicate resource rule '\(declaredResource.rule)' found for file at '\(path)'"))
                }
                matchedRule = Rule(rule: declaredResource.rule.fileRule, localization: declaredResource.localization)
            }
        }

        // Match any sources explicitly declared in the manifest file.
        if let declaredSources = self.declaredSources {
            for sourcePath in declaredSources {
                if path.contains(sourcePath) {
                    if matchedRule.rule != .none {
                        diags.emit(.error("duplicate rule found for file at '\(path)'"))
                    }

                    // Check for header files as they're allowed to be mixed with sources.
                    if let ext = path.extension,
                      FileRuleDescription.header.fileTypes.contains(ext) {
                        matchedRule = Rule(rule: .header, localization: nil)
                    } else if toolsVersion >= .v5_3 {
                        matchedRule = Rule(rule: .compile, localization: nil)
                    } else if let ext = path.extension,
                      SupportedLanguageExtension.validExtensions(toolsVersion: toolsVersion).contains(ext) {
                        matchedRule = Rule(rule: .compile, localization: nil)
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
        if matchedRule.rule == .none {
            let effectiveRules: [FileRuleDescription] = {
                // Don't automatically match compile rules if target's sources are
                // explicitly declared in the package manifest.
                if target.sources != nil {
                    return self.rules.filter { $0.rule != .compile }
                }
                return self.rules
            }()

            if let needle = effectiveRules.first(where: { $0.match(path: path, toolsVersion: toolsVersion) }) {
                matchedRule = Rule(rule: needle.rule, localization: nil)
            } else if path.parentDirectory.extension == Resource.localizationDirectoryExtension {
                matchedRule = Rule(rule: .processResource, localization: nil)
            }
        }

        return matchedRule
    }

    /// Returns the `Resource` file associated with a file and a particular rule, if there is one.
    private func resource(for path: AbsolutePath, with rule: Rule) -> Resource? {
        switch rule.rule {
        case .compile, .header, .none, .modulemap:
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
                switch rule.localization  {
                case .default?: return defaultLocalization ?? "en"
                case .base?: return "Base"
                case nil: return nil
                }
            }()

            // If a resource is both inside a localization directory and has an explicit localization, it's ambiguous.
            guard implicitLocalization == nil || explicitLocalization == nil else {
                let relativePath = path.relative(to: targetPath)
                diags.emit(.localizationAmbiguity(path: relativePath, targetName: target.name))
                return nil
            }

            return Resource(rule: .process, path: path, localization: implicitLocalization ?? explicitLocalization)
        case .copy:
            return Resource(rule: .copy, path: path, localization: nil)
        }
    }

    private func diagnoseConflictingResources(in resources: [Resource]) {
        let duplicateResources = resources.spm_findDuplicateElements(by: \.destination)
        for resources in duplicateResources {
            diags.emit(.conflictingResource(path: resources[0].destination, targetName: target.name))

            for resource in resources {
                let relativePath = resource.path.relative(to: targetPath)
                diags.emit(.fileReference(path: relativePath))
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
                diags.emit(.copyConflictWithLocalizationDirectory(path: relativePath, targetName: target.name))
            }
        }
    }

    private func diagnoseLocalizedAndUnlocalizedVariants(in resources: [Resource]) {
        let resourcesByBasename = Dictionary(grouping: resources, by: { $0.path.basename })
        for (basename, resources) in resourcesByBasename {
            let hasLocalizations = resources.contains(where: { $0.localization != nil })
            let hasUnlocalized = resources.contains(where: { $0.localization == nil })
            if hasLocalizations && hasUnlocalized {
                diags.emit(.localizedAndUnlocalizedVariants(resource: basename, targetName: target.name))
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
                diags.emit(.missingDefaultLocalizationResource(
                    resource: basename,
                    targetName: target.name,
                    defaultLocalization: defaultLocalization))
            }
        }
    }

    private func diagnoseInfoPlistConflicts(in resources: [Resource]) {
        for resource in resources {
            if resource.destination == RelativePath("Info.plist") {
                diags.emit(.infoPlistResourceConflict(
                    path: resource.path.relative(to: targetPath),
                    targetName: target.name))
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
            if path.parentDirectory == packagePath {
                if path.basename == Manifest.filename { continue }
                if path.basename == "Package.resolved" { continue }

                // Ignore version-specific manifest files.
                if path.basename.hasPrefix(Manifest.basename + "@") && path.extension == "swift" {
                    continue
                }
            }

            // Ignore if this is an excluded path.
            if self.excludedPaths.contains(path) { continue }

            if fs.isSymlink(path) && !fs.exists(path, followSymlink: true) {
                diags.emit(.brokenSymlink(path), location: diagnosticLocation)
                continue
            }

            // Consider non-directories as source files.
            if !fs.isDirectory(path) {
                contents.append(path)
                continue
            }

            // At this point, path can only be a directory.
            //
            // Starting tools version with resources, pick directories as
            // sources that have an extension but are not explicitly
            // declared as sources in the manifest.
            if
                toolsVersion >= .v5_3 &&
                path.extension != nil &&
                path.extension != Resource.localizationDirectoryExtension &&
                !isDeclaredSource(path)
            {
                contents.append(path)
                continue
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
                diags.emit(.localizationDirectoryContainsSubDirectories(
                    localizationDirectory: relativePath,
                    targetName: target.name))
                continue
            }

            // Otherwise, add its content to the queue.
            let dirContents = diags.wrap {
                try fs.getDirectoryContents(path).map({ path.appending(component: $0) })
            }
            queue += dirContents ?? []
        }

        return contents
    }

    private var diagnosticLocation: DiagnosticLocation {
        return PackageLocation.Local(name: packageName, packagePath: packagePath)
    }
}

/// Describes a rule for including a source or resource file in a target.
public struct FileRuleDescription {
    /// A rule semantically describes a file/directory in a target.
    ///
    /// It is up to the build system to translate a rule into a build command.
    public enum Rule {
        /// The compile rule for `sources` in a package.
        case compile

        /// Process resource file rule for any type of platform-specific processing.
        ///
        /// This defaults to copy if there's no specialized behavior.
        case processResource

        /// The copy rule.
        case copy

        /// The modulemap rule.
        case modulemap

        /// A header file.
        case header

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
            rule: .processResource,
            toolsVersion: .v5_3,
            fileTypes: ["nib", "xib", "storyboard"]
        )
    }()

    /// File types related to the asset catalog.
    public static let assetCatalog: FileRuleDescription = {
        .init(
            rule: .processResource,
            toolsVersion: .v5_3,
            fileTypes: ["xcassets"]
        )
    }()

    /// File types related to the CoreData.
    public static let coredata: FileRuleDescription = {
        .init(
            rule: .processResource,
            toolsVersion: .v5_3,
            fileTypes: ["xcdatamodeld", "xcdatamodel", "xcmappingmodel"]
        )
    }()

    /// File types related to Metal.
    public static let metal: FileRuleDescription = {
        .init(
            rule: .processResource,
            toolsVersion: .v5_3,
            fileTypes: ["metal"]
        )
    }()

    /// List of all the builtin rules.
    public static let builtinRules: [FileRuleDescription] = [
        swift,
        clang,
        asm,
        modulemap,
        header,
    ] + xcbuildFileTypes

    /// List of file types that requires the Xcode build system.
    public static let xcbuildFileTypes: [FileRuleDescription] = [
        xib,
        assetCatalog,
        coredata,
        metal,
    ]
}

extension TargetDescription.Resource.Rule {
    fileprivate var fileRule: FileRuleDescription.Rule {
        switch self {
        case .process:
            return .processResource
        case .copy:
            return .copy
        }
    }
}

extension Diagnostic.Message {
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
