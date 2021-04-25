/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility
import Foundation


/// Extensions on Manifest for generating source code expressing its contents
/// in canonical declarative form.  Note that this bakes in the results of any
/// algorithmically generated manifest content, so it is not suitable for the
/// mechanical editing of package manifests.  Rather, it is intended for such
/// tasks as manifest creation as part of package instantiation, etc.
extension Manifest {
    
    /// Generates and returns a string containing the contents of the manifest
    /// in canonical declarative form.
    public var generatedManifestFileContents: String {
        /// Only write out the major and minor (not patch) versions of the
        /// tools version, since the patch version doesn't change semantics.
        /// We leave out the spacer if the tools version doesn't support it.
        return """
            // swift-tools-version:\(toolsVersion < .v5_4 ? "" : " ")\(toolsVersion.major).\(toolsVersion.minor)
            import PackageDescription

            let package = \(SourceCodeFragment(from: self).generateSourceCode())
            """
    }
}


/// Convenience initializers for package manifest structures.
fileprivate extension SourceCodeFragment {
    
    /// Instantiates a SourceCodeFragment to represent an entire manifest.
    init(from manifest: Manifest) {
        var params: [SourceCodeFragment] = []
        
        params.append(SourceCodeFragment(key: "name", string: manifest.name))
        
        if let defaultLoc = manifest.defaultLocalization {
            params.append(SourceCodeFragment(key: "defaultLocalization", string: defaultLoc))
        }
        
        if !manifest.platforms.isEmpty {
            let nodes = manifest.platforms.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "platforms", subnodes: nodes))
        }
        
        if let pkgConfig = manifest.pkgConfig {
            params.append(SourceCodeFragment(key: "pkgConfig", string: pkgConfig))
        }
        
        if let systemPackageProviders = manifest.providers, !systemPackageProviders.isEmpty {
            let nodes = systemPackageProviders.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "providers", subnodes: nodes))
        }

        if !manifest.products.isEmpty {
            let nodes = manifest.products.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "products", subnodes: nodes))
        }

        if !manifest.dependencies.isEmpty {
            let nodes = manifest.dependencies.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "dependencies", subnodes: nodes))
        }

        if !manifest.targets.isEmpty {
            let nodes = manifest.targets.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "targets", subnodes: nodes))
        }
        
        if let swiftLanguageVersions = manifest.swiftLanguageVersions {
            let nodes = swiftLanguageVersions.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "swiftLanguageVersions", subnodes: nodes, multiline: false))
        }

        if let cLanguageStandard = manifest.cLanguageStandard {
            // NOTE: This could be cleaned up to use the nicer accessors.
            let node = SourceCodeFragment("CLanguageStandard", delimiters: .parentheses, multiline: false, subnodes: [SourceCodeFragment(key: "rawValue", string: cLanguageStandard)])
            params.append(SourceCodeFragment(key: "cLanguageStandard", subnode: node))
        }

        if let cxxLanguageStandard = manifest.cxxLanguageStandard {
            // NOTE: This could be cleaned up to use the nicer accessors.
            let node = SourceCodeFragment("CXXLanguageStandard", delimiters: .parentheses, multiline: false, subnodes: [SourceCodeFragment(key: "rawValue", string: cxxLanguageStandard)])
            params.append(SourceCodeFragment(key: "cxxLanguageStandard", subnode: node))
        }

        self.init("Package", delimiters: .parentheses, subnodes: params)
    }
    
    /// Instantiates a SourceCodeFragment to represent a single platform.
    init(from platform: PlatformDescription) {
        // NOTE: This could be cleaned up to use the nicer version accessors.
        switch platform.platformName {
        case "macos":
            self.init(enum: "macOS", string: platform.version)
        case "maccatalyst":
            self.init(enum: "macCatalyst", string: platform.version)
        case "ios":
            self.init(enum: "iOS", string: platform.version)
        case "tvos":
            self.init(enum: "tvOS", string: platform.version)
        case "watchos":
            self.init(enum: "watchOS", string: platform.version)
        case "driverkit":
            self.init(enum: "DriverKit", string: platform.version)
        default:
            self.init(enum: platform.platformName, string: platform.version)
        }
    }
    
    /// Instantiates a SourceCodeFragment to represent a single package dependency.
    init(from dependency: PackageDependencyDescription) {
        var params: [SourceCodeFragment] = []
        if let explicitName = dependency.explicitNameForTargetDependencyResolutionOnly {
            params.append(SourceCodeFragment(key: "name", string: explicitName))
        }
        switch dependency {
        case .local(let data):
            params.append(SourceCodeFragment(key: "path", string: data.path.pathString))
        case .scm(let data):
            params.append(SourceCodeFragment(key: "url", string: data.location))
            switch data.requirement {
            case .exact(let version):
                params.append(SourceCodeFragment(enum: "exact", string: "\(version)"))
            case .range(let range):
                params.append(SourceCodeFragment("\"\(range.lowerBound)\"..<\"\(range.upperBound)\""))
            case .revision(let revision):
                params.append(SourceCodeFragment(enum: "revision", string: revision))
            case .branch(let branch):
                params.append(SourceCodeFragment(enum: "branch", string: branch))
            }
        }
        self.init(enum: "package", subnodes: params)
    }
    
    /// Instantiates a SourceCodeFragment to represent a single product.
    init(from product: ProductDescription) {
        var params: [SourceCodeFragment] = []
        params.append(SourceCodeFragment(key: "name", string: product.name))
        if !product.targets.isEmpty {
            params.append(SourceCodeFragment(key: "targets", strings: product.targets))
        }
        switch product.type {
        case .library(let type):
            if type != .automatic {
                params.append(SourceCodeFragment(key: "type", enum: type.rawValue))
            }
            self.init(enum: "library", subnodes: params, multiline: true)
        case .executable:
            self.init(enum: "executable", subnodes: params, multiline: true)
        case .plugin:
            self.init(enum: "plugin", subnodes: params, multiline: true)
        case .test:
            self.init(enum: "test", subnodes: params, multiline: true)
        }
    }
    
    /// Instantiates a SourceCodeFragment to represent a single target.
    init(from target: TargetDescription) {
        var params: [SourceCodeFragment] = []

        params.append(SourceCodeFragment(key: "name", string: target.name))
        
        if let pluginCapability = target.pluginCapability {
            let node = SourceCodeFragment(from: pluginCapability)
            params.append(SourceCodeFragment(key: "capability", subnode: node))
        }

        if !target.dependencies.isEmpty {
            let nodes = target.dependencies.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "dependencies", subnodes: nodes))
        }

        if let path = target.path {
            params.append(SourceCodeFragment(key: "path", string: path))
        }

        if let url = target.url {
            params.append(SourceCodeFragment(key: "url", string: url))
        }

        if !target.exclude.isEmpty {
            params.append(SourceCodeFragment(key: "exclude", strings: target.exclude))
        }

        if let sources = target.sources, !sources.isEmpty {
            params.append(SourceCodeFragment(key: "sources", strings: sources))
        }

        if !target.resources.isEmpty {
            let nodes = target.resources.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "resources", subnodes: nodes))
        }

        if let publicHeadersPath = target.publicHeadersPath {
            params.append(SourceCodeFragment(key: "publicHeadersPath", string: publicHeadersPath))
        }

        if let pkgConfig = target.pkgConfig {
            params.append(SourceCodeFragment(key: "pkgConfig", string: pkgConfig))
        }
        
        if let systemPackageProviders = target.providers, !systemPackageProviders.isEmpty {
            let nodes = systemPackageProviders.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "providers", subnodes: nodes))
        }

        let cSettings = target.settings.filter{ $0.tool == .c }
        if !cSettings.isEmpty {
            let nodes = cSettings.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "cSettings", subnodes: nodes))
        }

        let cxxSettings = target.settings.filter{ $0.tool == .cxx }
        if !cxxSettings.isEmpty {
            let nodes = cxxSettings.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "cxxSettings", subnodes: nodes))
        }

        let swiftSettings = target.settings.filter{ $0.tool == .swift }
        if !swiftSettings.isEmpty {
            let nodes = swiftSettings.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "swiftSettings", subnodes: nodes))
        }

        let linkerSettings = target.settings.filter{ $0.tool == .linker }
        if !linkerSettings.isEmpty {
            let nodes = linkerSettings.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "linkerSettings", subnodes: nodes))
        }

        if let checksum = target.checksum {
            params.append(SourceCodeFragment(key: "checksum", string: checksum))
        }
        
        switch target.type {
        case .regular:
            self.init(enum: "target", subnodes: params, multiline: true)
        case .executable:
            self.init(enum: "executableTarget", subnodes: params, multiline: true)
        case .test:
            self.init(enum: "testTarget", subnodes: params, multiline: true)
        case .system:
            self.init(enum: "systemLibrary", subnodes: params, multiline: true)
        case .binary:
            self.init(enum: "binaryTarget", subnodes: params, multiline: true)
        case .plugin:
            self.init(enum: "plugin", subnodes: params, multiline: true)
        }
    }

    /// Instantiates a SourceCodeFragment to represent a single target dependency.
    init(from dependency: TargetDescription.Dependency) {
        var params: [SourceCodeFragment] = []

        switch dependency {
        case .target(name: let name, condition: let condition):
            params.append(SourceCodeFragment(key: "name", string: name))
            if let condition = condition {
                params.append(SourceCodeFragment(key: "condition", subnode: SourceCodeFragment(from: condition)))
            }
            self.init(enum: "target", subnodes: params)
            
        case .product(name: let name, package: let packageName, condition: let condition):
            params.append(SourceCodeFragment(key: "name", string: name))
            if let packageName = packageName {
                params.append(SourceCodeFragment(key: "package", string: packageName))
            }
            if let condition = condition {
                params.append(SourceCodeFragment(key: "condition", subnode: SourceCodeFragment(from: condition)))
            }
            self.init(enum: "product", subnodes: params)
            
        case .byName(name: let name, condition: let condition):
            if let condition = condition {
                params.append(SourceCodeFragment(key: "name", string: name))
                params.append(SourceCodeFragment(key: "condition", subnode: SourceCodeFragment(from: condition)))
                self.init(enum: "byName", subnodes: params)
            }
            else {
                self.init(name.quotedForPackageManifest)
            }
        }
    }
    
    /// Instantiates a SourceCodeFragment to represent a single package condition.
    init(from condition: PackageConditionDescription) {
        var params: [SourceCodeFragment] = []
        let platformNodes: [SourceCodeFragment] = condition.platformNames.map { platformName in
            switch platformName {
            case "macos": return SourceCodeFragment(enum: "macOS")
            case "maccatalyst": return SourceCodeFragment(enum: "macCatalyst")
            case "ios": return SourceCodeFragment(enum: "iOS")
            case "tvos": return SourceCodeFragment(enum: "tvOS")
            case "watchos": return SourceCodeFragment(enum: "watchOS")
            case "driverkit": return SourceCodeFragment(enum: "DriverKit")
            default: return SourceCodeFragment(enum: platformName)
            }
        }
        if !platformNodes.isEmpty {
            params.append(SourceCodeFragment(key: "platforms", subnodes: platformNodes, multiline: false))
        }
        if let configName = condition.config {
            params.append(SourceCodeFragment(key: "configuration", enum: configName))
        }
        self.init(enum: "when", subnodes: params)
    }

    /// Instantiates a SourceCodeFragment to represent a single Swift language version.
    init(from version: SwiftLanguageVersion) {
        switch version {
        case .v3:
            self.init(enum: "v3")
        case .v4:
            self.init(enum: "v4")
        case .v4_2:
            self.init(enum: "v4_2")
        case .v5:
            self.init(enum: "v5")
        default:
            self.init(enum: "version", subnodes: [SourceCodeFragment(string: version.rawValue)])
        }
    }

    /// Instantiates a SourceCodeFragment to represent a single system package provider.
    init(from systemPackageProvider: SystemPackageProviderDescription) {
        switch systemPackageProvider {
        case .brew(let names):
            let params = [SourceCodeFragment(strings: names)]
            self.init(enum: "brew", subnodes: params)
        case .apt(let names):
            let params = [SourceCodeFragment(strings: names)]
            self.init(enum: "apt", subnodes: params)
        case .yum(let names):
            let params = [SourceCodeFragment(strings: names)]
            self.init(enum: "yum", subnodes: params)
        }
    }

    /// Instantiates a SourceCodeFragment to represent a single system package provider.
    init(from resource: TargetDescription.Resource) {
        var params: [SourceCodeFragment] = []
        params.append(SourceCodeFragment(string: resource.path))
        if let localization = resource.localization {
            params.append(SourceCodeFragment(key: "localization", enum: localization.rawValue))
        }
        switch resource.rule {
        case .process:
            self.init(enum: "process", subnodes: params)
        case .copy:
            self.init(enum: "copy", subnodes: params)
        }
    }

    /// Instantiates a SourceCodeFragment to represent a single plugin capability.
    init(from capability: TargetDescription.PluginCapability) {
        switch capability {
        case .buildTool:
            self.init(enum: "buildTool", subnodes: [])
        }
    }

    /// Instantiates a SourceCodeFragment to represent a single target build setting.
    init(from setting: TargetBuildSettingDescription.Setting) {
        var params: [SourceCodeFragment] = []

        switch setting.name {
        case .headerSearchPath, .linkedLibrary, .linkedFramework:
            assert(setting.value.count == 1)
            params.append(SourceCodeFragment(string: setting.value[0]))
            if let condition = setting.condition {
                params.append(SourceCodeFragment(from: condition))
            }
            self.init(enum: setting.name.rawValue, subnodes: params)
        case .define:
            assert(setting.value.count == 1)
            let parts = setting.value[0].split(separator: "=", maxSplits: 1)
            assert(parts.count == 1 || parts.count == 2)
            params.append(SourceCodeFragment(string: String(parts[0])))
            if parts.count == 2 {
                params.append(SourceCodeFragment(key: "to", string: String(parts[1])))
            }
            if let condition = setting.condition {
                params.append(SourceCodeFragment(from: condition))
            }
            self.init(enum: setting.name.rawValue, subnodes: params)
        case .unsafeFlags:
            params.append(SourceCodeFragment(strings: setting.value))
            if let condition = setting.condition {
                params.append(SourceCodeFragment(from: condition))
            }
            self.init(enum: setting.name.rawValue, subnodes: params)
        }
    }
}


/// Convenience initializers for key-value pairs of simple types.  These make
/// the logic above much simpler.
fileprivate extension SourceCodeFragment {
    
    /// Initializes a SourceCodeFragment for a boolean in a generated manifest.
    init(key: String? = nil, boolean: Bool) {
        let prefix = key.map{ $0 + ": " } ?? ""
        self.init(prefix + (boolean ? "true" : "false"))
    }

    /// Initializes a SourceCodeFragment for a quoted string in a generated manifest.
    init(key: String? = nil, string: String) {
        let prefix = key.map{ $0 + ": " } ?? ""
        self.init(prefix + string.quotedForPackageManifest)
    }

    /// Initializes a SourceCodeFragment for an enum in a generated manifest.
    init(key: String? = nil, enum: String, string: String) {
        let prefix = key.map{ $0 + ": " } ?? ""
        let subnode = SourceCodeFragment(string: string)
        self.init(prefix + "." + `enum`, delimiters: .parentheses, multiline: false, subnodes: [subnode])
    }

    /// Initializes a SourceCodeFragment for an enum in a generated manifest.
    init(key: String? = nil, enum: String, strings: [String]) {
        let prefix = key.map{ $0 + ": " } ?? ""
        let subnodes = strings.map{ SourceCodeFragment($0.quotedForPackageManifest) }
        self.init(prefix + "." + `enum`, delimiters: .parentheses, multiline: false, subnodes: subnodes)
    }

    /// Initializes a SourceCodeFragment for an enum in a generated manifest.
    init(key: String? = nil, enum: String, subnodes: [SourceCodeFragment]? = nil, multiline: Bool = false) {
        let prefix = key.map{ $0 + ": " } ?? ""
        self.init(prefix + "." + `enum`, delimiters: .parentheses, multiline: multiline, subnodes: subnodes)
    }

    /// Initializes a SourceCodeFragment for a string list in a generated manifest.
    init(key: String? = nil, strings: [String], multiline: Bool = false) {
        let prefix = key.map{ $0 + ": " } ?? ""
        let subnodes = strings.map{ SourceCodeFragment($0.quotedForPackageManifest) }
        self.init(prefix, delimiters: .brackets, multiline: multiline, subnodes: subnodes)
    }

    /// Initializes a SourceCodeFragment for a node in a generated manifest.
    init(key: String? = nil, subnode: SourceCodeFragment) {
        let prefix = key.map{ $0 + ": " } ?? ""
        self.init(prefix, delimiters: .none, multiline: false, subnodes: [subnode])
    }

    /// Initializes a SourceCodeFragment for a list of nodes in a generated manifest.
    init(key: String? = nil, subnodes: [SourceCodeFragment], multiline: Bool = true) {
        let prefix = key.map{ $0 + ": " } ?? ""
        self.init(prefix, delimiters: .brackets, multiline: multiline, subnodes: subnodes)
    }
}



/// Helper type to emit source code.  Represents one node of source code, as a
/// arbitrary string followed by an optional child list, optionally enclosed in
/// a pair of delimiters.  The code generation works by creating source code
/// fragments and then rendering them as source code with proper formatting.
fileprivate struct SourceCodeFragment {
    let literal: String
    var delimiters: Delimiters
    var multiline: Bool
    var subnodes: [SourceCodeFragment]?

    enum Delimiters {
        case none
        case brackets
        case parentheses
    }
    
    init(_ literal: String, delimiters: Delimiters = .none,
         multiline: Bool = true, subnodes: [SourceCodeFragment]? = nil) {
        self.literal = literal
        self.delimiters = delimiters
        self.multiline = multiline
        self.subnodes = subnodes
    }
    
    func generateSourceCode(indent: String = "") -> String {
        var string = literal
        if let subnodes = subnodes {
            switch delimiters {
            case .none: break
            case .brackets: string.append("[")
            case .parentheses: string.append("(")
            }
            if multiline { string.append("\n") }
            for (idx, subnode) in subnodes.enumerated() {
                let subindent = indent + "    "
                if multiline { string.append(subindent) }
                string.append(subnode.generateSourceCode(indent: subindent))
                if idx < subnodes.count-1 {
                    string.append(multiline ? ",\n" : ", ")
                }
            }
            if multiline {
                string.append("\n")
                string.append(indent)
            }
            switch delimiters {
            case .none: break
            case .brackets: string.append("]")
            case .parentheses: string.append(")")
            }
        }
        return string
    }
}


fileprivate extension String {
    
    var quotedForPackageManifest: String {
        return "\"" + self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }
}
