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
        additionalFileRules: [FileRuleDescription] = [],
        toolsVersion: ToolsVersion = .currentToolsVersion,
        fs: FileSystem = localFileSystem,
        diags: DiagnosticsEngine
    ) {
        self.packageName = packageName
        self.packagePath = packagePath
        self.target = target
        self.diags = diags
        self.targetPath = path
        self.rules = FileRuleDescription.builtinRules + additionalFileRules
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
    public func run() throws -> (sources: Sources, resources: [Resource]) {
        let contents = computeContents()
        var pathToRule: [AbsolutePath: FileRuleDescription.Rule] = [:]

        for path in contents {
            pathToRule[path] = findRule(for: path)
        }

        // Emit an error if we found files without a matching rule in
        // tools version >= vNext. This will be activated once resources
        // support is complete.
        if toolsVersion >= .vNext {
            let filesWithNoRules = pathToRule.filter{ $0.value == .none }
            if !filesWithNoRules.isEmpty {
                var error = "found \(filesWithNoRules.count) file(s) which are unhandled; explicitly declare them as resources or exclude from the target\n"
                for (file, _) in filesWithNoRules {
                    error += "    " + file.pathString + "\n"
                }
                diags.emit(.error(error))
            }
        }

        let compilePaths = pathToRule.filter{ $0.value == .compile }.map{ $0.key }
        let sources = Sources(paths: compilePaths, root: targetPath)

        let resources: [Resource] = pathToRule.compactMap {
            switch $0.value {
            case .compile, .none, .modulemap, .header:
                return nil
            case .processResource:
                return Resource(rule: .process, path: $0.key)
            case .copy:
                return Resource(rule: .copy, path: $0.key)
            }
        }

        // Diagnose conflicting resources.
        let duplicateResources = resources
            .spm_findDuplicateElements(by: \.path.basename)
        for resources in duplicateResources {
            let filename = resources[0].path.basename
            diags.emit(.conflictingResource(filename: filename, targetName: target.name))

            for resource in resources {
                let relativePath = resource.path.relative(to: targetPath)
                diags.emit(.fileReference(path: relativePath))
            }
        }

        diagnoseInfoPlistConflicts(in: resources)

        // It's an error to contain mixed language source files.
        if sources.containsMixedLanguage {
            throw Target.Error.mixedSources(targetPath)
        }

        return (sources, resources)
    }

    /// Find the rule for the given path.
    private func findRule(for path: AbsolutePath) -> FileRuleDescription.Rule {
        var matchedRule: FileRuleDescription.Rule = .none

        // First match any resources explicitly declared in the manifest file.
        for declaredResource in target.resources {
            let resourcePath = self.targetPath.appending(RelativePath(declaredResource.path))
            if path.contains(resourcePath) {
                if matchedRule != .none {
                    diags.emit(.error("Duplicate rule \(declaredResource.rule) found for \(path)"))
                }
                matchedRule = declaredResource.rule.fileRule
            }
        }

        // Match any sources explicitly declared in the manifest file.
        if let declaredSources = self.declaredSources {
            for sourcePath in declaredSources {
                if path.contains(sourcePath) {
                    if matchedRule != .none {
                        diags.emit(.error("Duplicate rule compile found for \(path)"))
                    }

                    // Check for header files as they're allowed to be mixed with sources.
                    if let ext = path.extension,
                      FileRuleDescription.header.fileTypes.contains(ext) {
                        matchedRule = .header
                    } else {
                        matchedRule = .compile
                    }
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
            }
        }

        return matchedRule
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

        while let curr = queue.popLast() {
            // Ignore dot files.
            if curr.basename.hasPrefix(".") { continue }

            // Ignore xcodeproj and playground directories.
            //
            // FIXME: Ignore lproj directories until we add localization support.
            if ["xcodeproj", "playground", "xcworkspace", "lproj"].contains(curr.extension) { continue }

            // Ignore manifest files.
            if curr.parentDirectory == packagePath {
                if curr.basename == Manifest.filename { continue }
                if curr.basename == "Package.resolved" { continue }

                // Ignore version-specific manifest files.
                if curr.basename.hasPrefix(Manifest.basename + "@") &&
                    curr.extension == "swift" {
                    continue
                }
            }

            // Ignore if this is an excluded path.
            if self.excludedPaths.contains(curr) { continue }

            if fs.isSymlink(curr) && !fs.exists(curr, followSymlink: true) {
                diags.emit(.brokenSymlink(curr), location: diagnosticLocation)
                continue
            }

            // Consider non-directories as source files.
            if !fs.isDirectory(curr) {
                contents.append(curr)
                continue
            }

            // At this point, curr can only be a directory.
            //
            // Starting tools version with resources, pick directories as
            // sources that have an extension but are not explicitly
            // declared as sources in the manifest.
            if toolsVersion >= .vNext && curr.extension != nil && !isDeclaredSource(curr) {
                contents.append(curr)
                continue
            }

            // Check if the directory is marked to be copied.
            let directoryMarkedToBeCopied = target.resources.contains{ resource in
                let resourcePath = self.targetPath.appending(RelativePath(resource.path))
                if resource.rule == .copy && resourcePath == curr {
                    return true
                }
                return false
            }

            // If the directory is marked to be copied, don't look inside it.
            if directoryMarkedToBeCopied {
                contents.append(curr)
                continue
            }

            // Otherwise, add its content to the queue.
            let dirContents = diags.wrap {
                try fs.getDirectoryContents(curr).map{ curr.appending(component: $0) }
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
    public static var swift: FileRuleDescription = {
        .init(
            rule: .compile,
            toolsVersion: .minimumRequired,
            fileTypes: ["swift"]
        )
    }()

    /// The clang compiler rule.
    public static var clang: FileRuleDescription = {
        .init(
            rule: .compile,
            toolsVersion: .minimumRequired,
            fileTypes: ["c", "m", "mm", "cc", "cpp", "cxx"]
        )
    }()

    /// The rule for compiling asm files.
    public static var asm: FileRuleDescription = {
        .init(
            rule: .compile,
            toolsVersion: .v5,
            fileTypes: ["s", "S"]
        )
    }()

    /// The rule for detecting modulemap files.
    public static var modulemap: FileRuleDescription = {
        .init(
            rule: .modulemap,
            toolsVersion: .minimumRequired,
            fileTypes: ["modulemap"]
        )
    }()

    /// The rule for detecting header files.
    public static var header: FileRuleDescription = {
        .init(
            rule: .header,
            toolsVersion: .minimumRequired,
            fileTypes: ["h"]
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
