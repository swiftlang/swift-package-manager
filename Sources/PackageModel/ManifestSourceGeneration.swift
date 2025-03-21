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

/// Extensions on Manifest for generating source code expressing its contents
/// in canonical declarative form.  Note that this bakes in the results of any
/// algorithmically generated manifest content, so it is not suitable for the
/// mechanical editing of package manifests.  Rather, it is intended for such
/// tasks as manifest creation as part of package instantiation, etc.
extension Manifest {
    
    /// Generates and returns a string containing the contents of the manifest
    /// in canonical declarative form.
    /// 
    /// - Parameters:
    ///   - packageDirectory: Directory of the manifest's package (for purposes of making strings relative).
    ///   - toolsVersionHeaderComment: Optional string to add to the `swift-tools-version` header (it will be ignored).
    ///   - additionalImportModuleNames: Names of any modules to import besides PackageDescription (would commonly contain custom product type definitions).
    ///   - customProductTypeSourceGenerator: Closure that will be called once for each custom product type in the manifest; it should return a SourceCodeFragment for the product type.
    /// 
    /// Returns: a string containing the full source code for the manifest.
    public func generateManifestFileContents(
        packageDirectory: AbsolutePath,
        toolsVersionHeaderComment: String? = .none,
        additionalImportModuleNames: [String] = [],
        customProductTypeSourceGenerator: ManifestCustomProductTypeSourceGenerator? = .none,
        overridingToolsVersion: ToolsVersion? = nil
    ) rethrows -> String {
        let toolsVersion = overridingToolsVersion ?? self.toolsVersion
        
        // Generate the source code fragment for the top level of the package
        // expression.
        let packageExprFragment = try SourceCodeFragment(
            from: self,
            packageDirectory: packageDirectory,
            customProductTypeSourceGenerator: customProductTypeSourceGenerator,
            toolsVersion: toolsVersion)
        
        // Generate the source code from the module names and code fragment.
        // We only write out the major and minor (not patch) versions of the
        // tools version, since the patch version doesn't change semantics.
        // We leave out the spacer if the tools version doesn't support it.
        let toolsVersionSuffix = "\(toolsVersionHeaderComment.map{ "; \($0)" } ?? "")"
        return """
            \(toolsVersion.specification(roundedTo: .minor))\(toolsVersionSuffix)
            import PackageDescription
            \(additionalImportModuleNames.map{ "import \($0)\n" }.joined())
            let package = \(packageExprFragment.generateSourceCode())
            """
    }
}

/// Constructs and returns a SourceCodeFragment that represents the instantiation of a custom product type with the specified identifier and having the given serialized parameters (the contents of whom are a private matter between the serialized form in PackageDescription and the client). The generated source code should, if evaluated as a part of a package manifest, result in the same serialized parameters.
public typealias ManifestCustomProductTypeSourceGenerator = (ProductDescription) throws -> SourceCodeFragment?


/// Convenience initializers for package manifest structures.
fileprivate extension SourceCodeFragment {

    /// Instantiates a SourceCodeFragment to represent an entire manifest.
    init(
        from manifest: Manifest,
        packageDirectory: AbsolutePath,
        customProductTypeSourceGenerator: ManifestCustomProductTypeSourceGenerator?,
        toolsVersion: ToolsVersion
    ) rethrows {
        var params: [SourceCodeFragment] = []
        
        params.append(SourceCodeFragment(key: "name", string: manifest.displayName))
        
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
            let nodes = try manifest.products.map{ try SourceCodeFragment(from: $0, customProductTypeSourceGenerator: customProductTypeSourceGenerator, toolsVersion: toolsVersion) }
            params.append(SourceCodeFragment(key: "products", subnodes: nodes))
        }

        if !manifest.dependencies.isEmpty {
            let nodes = manifest.dependencies.map{ SourceCodeFragment(from: $0, pathAnchor: packageDirectory) }
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
        case "visionos":
            self.init(enum: "visionOS", string: platform.version)
        case "driverkit":
            self.init(enum: "driverKit", string: platform.version)
        default:
            self.init(enum: "custom", subnodes: [ .init(string: platform.platformName), .init(key: "versionString", string: platform.version) ])
        }
    }
    
    /// Instantiates a SourceCodeFragment to represent a single package dependency.
    init(from dependency: PackageDependency, pathAnchor: AbsolutePath) {
        var params: [SourceCodeFragment] = []
        if let explicitName = dependency.explicitNameForModuleDependencyResolutionOnly {
            params.append(SourceCodeFragment(key: "name", string: explicitName))
        }
        switch dependency {
        case .fileSystem(let settings):
            let relPath = settings.path.relative(to: pathAnchor)
            params.append(SourceCodeFragment(key: "path", string: relPath.pathString))
        case .sourceControl(let settings):
            switch settings.location {
            case .local(let absPath):
                let relPath = absPath.relative(to: pathAnchor)
                params.append(SourceCodeFragment(key: "url", string: relPath.pathString))
            case .remote(let url):
                params.append(SourceCodeFragment(key: "url", string: url.absoluteString))
            }
            switch settings.requirement {
            case .exact(let version):
                params.append(SourceCodeFragment(enum: "exact", string: "\(version)"))
            case .range(let range):
                params.append(SourceCodeFragment("\"\(range.lowerBound)\"..<\"\(range.upperBound)\""))
            case .revision(let revision):
                params.append(SourceCodeFragment(enum: "revision", string: revision))
            case .branch(let branch):
                params.append(SourceCodeFragment(enum: "branch", string: branch))
            }
        case .registry(let settings):
            params.append(SourceCodeFragment(key: "identity", string: settings.identity.description))
            switch settings.requirement {
            case .exact(let version):
                params.append(SourceCodeFragment(enum: "exact", string: "\(version)"))
            case .range(let range):
                params.append(SourceCodeFragment("\"\(range.lowerBound)\"..<\"\(range.upperBound)\""))
            }
        }
        self.init(enum: "package", subnodes: params)
    }
    
    /// Instantiates a SourceCodeFragment to represent a single product. If there's a custom product generator, it gets
    /// a chance to generate the source code fragments before checking the default types.
    init(from product: ProductDescription, customProductTypeSourceGenerator: ManifestCustomProductTypeSourceGenerator?, toolsVersion: ToolsVersion) rethrows {
        // Use a custom source code fragment if we have a custom generator and it returns a value.
        if let customSubnode = try customProductTypeSourceGenerator?(product) {
            self = customSubnode
        }
        // Otherwise we use the default behavior.
        else {
            var params: [SourceCodeFragment] = []
            params.append(SourceCodeFragment(key: "name", string: product.name))
            if !product.targets.isEmpty && !product.type.isLibrary {
                params.append(SourceCodeFragment(key: "targets", strings: product.targets))
            }
            switch product.type {
            case .library(let type):
                if type != .automatic {
                    params.append(SourceCodeFragment(key: "type", enum: type.rawValue))
                }
                if !product.targets.isEmpty {
                    params.append(SourceCodeFragment(key: "targets", strings: product.targets))
                }
                self.init(enum: "library", subnodes: params, multiline: true)
            case .executable:
                // For iOSApplication targets, we temporarily do something special
                // This will be generalized once we are sure of how it should look.
                let isIOSApp = product.settings.contains(where: {
                    // iOS apps are currently identifier by an iOSAppInfo product
                    // setting.
                    if case .iOSAppInfo(_) = $0 {
                        return true
                    }
                    return false
                })
                if isIOSApp {
                    // Create a parameter for each of the product settings.
                    for setting in product.settings {
                        let subnode = SourceCodeFragment(from: setting, toolsVersion: toolsVersion)
                        switch setting {
                        case .iOSAppInfo(_):
                            // For the app info only, we hoist the subnodes of the
                            // initializer out to the top level, since that is the
                            // form of the instantiator function.
                            params.append(contentsOf: subnode.subnodes?.first?.subnodes ?? [])
                        default:
                            // Other product settings are just added as they are.
                            params.append(subnode)
                        }
                    }
                    self.init(enum: "iOSApplication", subnodes: params, multiline: true)
                }
                else {
                    self.init(enum: "executable", subnodes: params, multiline: true)
                }
            case .snippet:
                self.init(enum: "sample", subnodes: params, multiline: true)
            case .plugin:
                self.init(enum: "plugin", subnodes: params, multiline: true)
            case .test:
                self.init(enum: "test", subnodes: params, multiline: true)
            case .macro:
                self.init(enum: "macro", subnodes: params, multiline: true)
            }
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
        case .macro:
            self.init(enum: "macro", subnodes: params, multiline: true)
        }
    }

    /// Instantiates a SourceCodeFragment to represent a single target dependency.
    init(from dependency: TargetDescription.Dependency) {
        var params: [SourceCodeFragment] = []

        switch dependency {
        case .target(name: let name, condition: let condition):
            params.append(SourceCodeFragment(key: "name", string: name))
            if let condition {
                params.append(SourceCodeFragment(key: "condition", subnode: SourceCodeFragment(from: condition)))
            }
            self.init(enum: "target", subnodes: params)
            
        case .product(name: let name, package: let packageName, moduleAliases: let aliases, condition: let condition):
            params.append(SourceCodeFragment(key: "name", string: name))
            if let packageName {
                params.append(SourceCodeFragment(key: "package", string: packageName))
            }
            if let aliases {
                let vals = aliases.map { SourceCodeFragment(key: $0.key.quotedForPackageManifest, string: $0.value) }
                params.append(SourceCodeFragment(key: "moduleAliases", subnodes: vals))
            }
            if let condition {
                params.append(SourceCodeFragment(key: "condition", subnode: SourceCodeFragment(from: condition)))
            }
            self.init(enum: "product", subnodes: params)
            
        case .byName(name: let name, condition: let condition):
            if let condition {
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
            case "visionos": return SourceCodeFragment(enum: "visionOS")
            case "driverkit": return SourceCodeFragment(enum: "driverKit")
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
        case .nuget(let names):
            let params = [SourceCodeFragment(strings: names)]
            self.init(enum: "nuget", subnodes: params)
        case .pkg(let names):
            let params = [SourceCodeFragment(strings: names)]
            self.init(enum: "pkg", subnodes: params)
        }
    }

    /// Instantiates a SourceCodeFragment to represent a single system package provider.
    init(from resource: TargetDescription.Resource) {
        var params: [SourceCodeFragment] = []
        params.append(SourceCodeFragment(string: resource.path))
        switch resource.rule {
        case .process(let localization):
            if let localization {
                params.append(SourceCodeFragment(key: "localization", enum: localization.rawValue))
            }
            self.init(enum: "process", subnodes: params)
        case .copy:
            self.init(enum: "copy", subnodes: params)
        case .embedInCode:
            self.init(enum: "embedInCode", subnodes: params)
        }
    }

    /// Instantiates a SourceCodeFragment to represent a single plugin capability.
    init(from capability: TargetDescription.PluginCapability) {
        switch capability {
        case .buildTool:
            self.init(enum: "buildTool", subnodes: [])
        case .command(let intent, let permissions):
            var params: [SourceCodeFragment] = []
            params.append(SourceCodeFragment(key: "intent", subnode: .init(from: intent)))
            if !permissions.isEmpty {
                params.append(SourceCodeFragment(key: "permissions", subnodes: permissions.map{ .init(from: $0) }))
            }
            self.init(enum: "command", subnodes: params)
        }
    }

    /// Instantiates a SourceCodeFragment to represent a single plugin command intent.
    init(from intent: TargetDescription.PluginCommandIntent) {
        switch intent {
        case .documentationGeneration:
            self.init(enum: "documentationGeneration", subnodes: [])
        case .sourceCodeFormatting:
            self.init(enum: "sourceCodeFormatting", subnodes: [])
        case .custom(let verb, let description):
            let params = [
                SourceCodeFragment(key: "verb", string: verb),
                SourceCodeFragment(key: "description", string: description)
            ]
            self.init(enum: "custom", subnodes: params)
        }
    }

    init(from networkPermissionScope: TargetDescription.PluginNetworkPermissionScope) {
        switch networkPermissionScope {
        case .none:
            self.init(enum: "none")
        case .local(let ports):
            let ports = SourceCodeFragment(key: "ports", subnodes: ports.map { SourceCodeFragment("\($0)") })
            self.init(enum: "local", subnodes: [ports])
        case .all(let ports):
            let ports = SourceCodeFragment(key: "ports", subnodes: ports.map { SourceCodeFragment("\($0)") })
            self.init(enum: "all", subnodes: [ports])
        case .docker:
            self.init(enum: "docker")
        case .unixDomainSocket:
            self.init(enum: "unixDomainSocket")
        }
    }

    /// Instantiates a SourceCodeFragment to represent a single plugin permission.
    init(from permission: TargetDescription.PluginPermission) {
        switch permission {
        case .allowNetworkConnections(let scope, let reason):
            let scope = SourceCodeFragment(key: "scope", subnode: .init(from: scope))
            let reason = SourceCodeFragment(key: "reason", string: reason)
            self.init(enum: "allowNetworkConnections", subnodes: [scope, reason])
        case .writeToPackageDirectory(let reason):
            let param = SourceCodeFragment(key: "reason", string: reason)
            self.init(enum: "writeToPackageDirectory", subnodes: [param])
        }
    }

    /// Instantiates a SourceCodeFragment to represent a single target build setting.
    init(from setting: TargetBuildSettingDescription.Setting) {
        var params: [SourceCodeFragment] = []

        switch setting.kind {
        case .headerSearchPath(let value), .linkedLibrary(let value), .linkedFramework(let value), .enableUpcomingFeature(let value), .enableExperimentalFeature(let value):
            params.append(SourceCodeFragment(string: value))
            if let condition = setting.condition {
                params.append(SourceCodeFragment(from: condition))
            }
            self.init(enum: setting.kind.name, subnodes: params)
        case .strictMemorySafety:
          self.init(enum: setting.kind.name, subnodes: [])
        case .define(let value):
            let parts = value.split(separator: "=", maxSplits: 1)
            assert(parts.count == 1 || parts.count == 2)
            params.append(SourceCodeFragment(string: String(parts[0])))
            if parts.count == 2 {
                params.append(SourceCodeFragment(key: "to", string: String(parts[1])))
            }
            if let condition = setting.condition {
                params.append(SourceCodeFragment(from: condition))
            }
            self.init(enum: setting.kind.name, subnodes: params)
        case .interoperabilityMode(let lang):
            params.append(SourceCodeFragment(enum: lang.rawValue))
            self.init(enum: setting.kind.name, subnodes: params)
        case .unsafeFlags(let values):
            params.append(SourceCodeFragment(strings: values))
            if let condition = setting.condition {
                params.append(SourceCodeFragment(from: condition))
            }
            self.init(enum: setting.kind.name, subnodes: params)
        case .swiftLanguageMode(let version):
            params.append(SourceCodeFragment(from: version))
            if let condition = setting.condition {
                params.append(SourceCodeFragment(from: condition))
            }
            self.init(enum: setting.kind.name, subnodes: params)
        case .defaultIsolation(let isolation):
            switch isolation {
            case .MainActor:
                params.append(SourceCodeFragment("MainActor.self"))
            case .nonisolated:
                params.append(SourceCodeFragment("nil"))
            }
            if let condition = setting.condition {
                params.append(SourceCodeFragment(from: condition))
            }
            self.init(enum: setting.kind.name, subnodes: params)
        }
    }

    /// Instantiates a SourceCodeFragment from a single ProductSetting.
    init(from productSetting: ProductSetting, toolsVersion: ToolsVersion) {
        switch productSetting {
        case .bundleIdentifier(let value):
            self.init(key: "bundleIdentifier", string: value)
        case .teamIdentifier(let value):
            self.init(key: "teamIdentifier", string: value)
        case .displayVersion(let value):
            self.init(key: "displayVersion", string: value)
        case .bundleVersion(let value):
            self.init(key: "bundleVersion", string: value)
        case .iOSAppInfo(let value):
            self.init(key: "iOSAppInfo", subnode: SourceCodeFragment(from: value, toolsVersion: toolsVersion))
        }
    }

    /// Instantiates a SourceCodeFragment from a single ProductSetting.IOSAppInfo.
    init(from appInfo: ProductSetting.IOSAppInfo, toolsVersion: ToolsVersion) {
        var params: [SourceCodeFragment] = []
        if let appIcon = appInfo.appIcon {
            switch appIcon {
            case let .placeholder(icon):
                params.append(SourceCodeFragment(key: "appIcon", enum: "placeholder", subnodes: [SourceCodeFragment(from: icon)]))
            case let .asset(name):
                if toolsVersion < .v5_6 {
                    params.append(SourceCodeFragment(key: "iconAssetName", string: "\(name)"))
                }
                else {
                    params.append(SourceCodeFragment(key: "appIcon", enum: "asset", string: "\(name)"))
                }
            }
        }
        if let accentColor = appInfo.accentColor {
            switch accentColor {
            case let .presetColor(presetColor):
                params.append(SourceCodeFragment(key: "accentColor", enum: "presetColor", subnodes: [SourceCodeFragment(from: presetColor)]))
            case let .asset(name):
                if toolsVersion < .v5_6 {
                    params.append(SourceCodeFragment(key: "accentColorAssetName", string: "\(name)"))
                }
                else {
                    params.append(SourceCodeFragment(key: "accentColor", enum: "asset", string: "\(name)"))
                }
            }
        }
        params.append(SourceCodeFragment(key: "supportedDeviceFamilies", subnodes: appInfo.supportedDeviceFamilies.map{
            SourceCodeFragment(from: $0)
        }))
        params.append(SourceCodeFragment(key: "supportedInterfaceOrientations", subnodes: appInfo.supportedInterfaceOrientations.map{ SourceCodeFragment(from: $0)
        }))
        if !appInfo.capabilities.isEmpty {
            params.append(SourceCodeFragment(key: "capabilities", subnodes: appInfo.capabilities.map{ SourceCodeFragment(from: $0) }))
        }
        if let appCategory = appInfo.appCategory {
            params.append(SourceCodeFragment(subnode: SourceCodeFragment(from: appCategory)))
        }
        if let additionalInfoPlistContentFilePath = appInfo.additionalInfoPlistContentFilePath {
            params.append(SourceCodeFragment(key: "additionalInfoPlistContentFilePath", string: additionalInfoPlistContentFilePath))
        }
        self.init(enum: "init", subnodes: params, multiline: true)
    }
    
    /// Instantiates a SourceCodeFragment from a single ProductSetting.IOSAppInfo.AppIcon.PlaceholderIcon.
    init(from placeholderIcon: ProductSetting.IOSAppInfo.AppIcon.PlaceholderIcon) {
        self.init(key: "icon", enum: placeholderIcon.rawValue)
    }
    
    /// Instantiates a SourceCodeFragment from a single ProductSetting.IOSAppInfo.AccentColor.PresetColor.
    init(from presetColor: ProductSetting.IOSAppInfo.AccentColor.PresetColor) {
        self.init(enum: presetColor.rawValue)
    }

    /// Instantiates a SourceCodeFragment from a single ProductSetting.IOSAppInfo.DeviceFamily.
    init(from deviceFamily: ProductSetting.IOSAppInfo.DeviceFamily) {
        self.init(enum: deviceFamily.rawValue)
    }

    /// Instantiates a SourceCodeFragment from a single ProductSetting.IOSAppInfo.DeviceFamilyCondition.
    init(from deviceFamilyCondition: ProductSetting.IOSAppInfo.DeviceFamilyCondition) {
        let deviceFamilyNodes = deviceFamilyCondition.deviceFamilies.map{ SourceCodeFragment(from: $0) }
        let deviceFamiliesList = SourceCodeFragment(key: "deviceFamilies", subnodes: deviceFamilyNodes, multiline: false)
        self.init(enum: "when", subnodes: [deviceFamiliesList])
    }

    /// Instantiates a SourceCodeFragment from a single ProductSetting.IOSAppInfo.InterfaceOrientation.
    init(from orientation: ProductSetting.IOSAppInfo.InterfaceOrientation) {
        switch orientation {
        case .portrait(let condition):
            self.init(enum: "portrait", subnodes: condition.map{ [SourceCodeFragment(from: $0)] })
        case .portraitUpsideDown(let condition):
            self.init(enum: "portraitUpsideDown", subnodes: condition.map{ [SourceCodeFragment(from: $0)] })
        case .landscapeLeft(let condition):
            self.init(enum: "landscapeLeft", subnodes: condition.map{ [SourceCodeFragment(from: $0)] })
        case .landscapeRight(let condition):
            self.init(enum: "landscapeRight", subnodes: condition.map{ [SourceCodeFragment(from: $0)] })
        }
    }

    /// Instantiates a SourceCodeFragment from a single ProductSetting.IOSAppInfo.Capability.
    init(from capability: ProductSetting.IOSAppInfo.Capability) {
        var params: [SourceCodeFragment] = []
        if let purposeString = capability.purposeString {
            params.append(SourceCodeFragment(key: "purposeString", string: purposeString))
        }
        if let configuration = capability.appTransportSecurityConfiguration {
            params.append(SourceCodeFragment(key: "configuration", subnode: .init(from: configuration)))
        }
        if let bonjourServiceTypes = capability.bonjourServiceTypes {
            params.append(SourceCodeFragment(key: "bonjourServiceTypes", strings: bonjourServiceTypes))
        }
        if let fileAccessLocation = capability.fileAccessLocation {
            params.append(SourceCodeFragment(enum: fileAccessLocation))
        }
        if let fileAccessMode = capability.fileAccessMode {
            params.append(SourceCodeFragment(key: "mode", enum: fileAccessMode))
        }

        if let condition = capability.condition {
            params.append(SourceCodeFragment(from: condition))
        }
        self.init(enum: capability.purpose, subnodes: params)
    }

    /// Instantiates a SourceCodeFragment from a single ProductSetting.IOSAppInfo.AppTransportSecurityConfiguration.
    init(from configuration: ProductSetting.IOSAppInfo.AppTransportSecurityConfiguration) {
        var params: [SourceCodeFragment] = []
        if let allowsArbitraryLoadsInWebContent = configuration.allowsArbitraryLoadsInWebContent {
            params.append(SourceCodeFragment(key: "allowsArbitraryLoadsInWebContent", boolean: allowsArbitraryLoadsInWebContent))
        }
        if let allowsArbitraryLoadsForMedia = configuration.allowsArbitraryLoadsForMedia {
            params.append(SourceCodeFragment(key: "allowsArbitraryLoadsForMedia", boolean: allowsArbitraryLoadsForMedia))
        }
        if let allowsLocalNetworking = configuration.allowsLocalNetworking {
            params.append(SourceCodeFragment(key: "allowsLocalNetworking", boolean: allowsLocalNetworking))
        }
        if let exceptionDomains = configuration.exceptionDomains {
            let subnodes = exceptionDomains.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "exceptionDomains", subnodes: subnodes))
        }
        if let pinnedDomains = configuration.pinnedDomains {
            let subnodes = pinnedDomains.map{ SourceCodeFragment(from: $0) }
            params.append(SourceCodeFragment(key: "pinnedDomains", subnodes: subnodes))
        }
        self.init(enum: "init", subnodes: params, multiline: true)
    }

    /// Instantiates a SourceCodeFragment from a single ProductSetting.IOSAppInfo.AppTransportSecurityConfiguration.ExceptionDomain.
    init(from domain: ProductSetting.IOSAppInfo.AppTransportSecurityConfiguration.ExceptionDomain) {
        var params: [SourceCodeFragment] = []
        params.append(SourceCodeFragment(key: "domainName", string: domain.domainName))
        if let includesSubdomains = domain.includesSubdomains {
            params.append(SourceCodeFragment(key: "includesSubdomains", boolean: includesSubdomains))
        }
        if let exceptionAllowsInsecureHTTPLoads = domain.exceptionAllowsInsecureHTTPLoads {
            params.append(SourceCodeFragment(key: "exceptionAllowsInsecureHTTPLoads", boolean: exceptionAllowsInsecureHTTPLoads))
        }
        if let exceptionMinimumTLSVersion = domain.exceptionMinimumTLSVersion {
            params.append(SourceCodeFragment(key: "exceptionMinimumTLSVersion", string: exceptionMinimumTLSVersion))
        }
        if let exceptionRequiresForwardSecrecy = domain.exceptionRequiresForwardSecrecy {
            params.append(SourceCodeFragment(key: "exceptionRequiresForwardSecrecy", boolean: exceptionRequiresForwardSecrecy))
        }
        if let requiresCertificateTransparency = domain.requiresCertificateTransparency {
            params.append(SourceCodeFragment(key: "requiresCertificateTransparency", boolean: requiresCertificateTransparency))
        }
        self.init(enum: "init", subnodes: params, multiline: true)
    }

    /// Instantiates a SourceCodeFragment from a single ProductSetting.IOSAppInfo.AppTransportSecurityConfiguration.ExceptionDomain.
    init(from domain: ProductSetting.IOSAppInfo.AppTransportSecurityConfiguration.PinnedDomain) {
        var params: [SourceCodeFragment] = []
        params.append(SourceCodeFragment(key: "domainName", string: domain.domainName))
        if let includesSubdomains = domain.includesSubdomains {
            params.append(SourceCodeFragment(key: "includesSubdomains", boolean: includesSubdomains))
        }
        if let pinnedCAIdentities = domain.pinnedCAIdentities {
            let subnodes = pinnedCAIdentities.map{ SourceCodeFragment(stringPairs: $0.sorted{ $0.key < $1.key }.map{ ($0.key, $0.value) }) }
            params.append(SourceCodeFragment(key: "pinnedCAIdentities", subnodes: subnodes))
        }
        if let pinnedLeafIdentities = domain.pinnedLeafIdentities {
            let subnodes = pinnedLeafIdentities.map{ SourceCodeFragment(stringPairs: $0.sorted{ $0.key < $1.key }.map{ ($0.key, $0.value) }) }
            params.append(SourceCodeFragment(key: "pinnedLeafIdentities", subnodes: subnodes))
        }
        self.init(enum: "init", subnodes: params, multiline: true)
    }
    
    /// Instantiates a SourceCodeFragment from a single ProductSetting.IOSAppInfo.AppCategory.
    init(from appCategory: ProductSetting.IOSAppInfo.AppCategory) {
        switch appCategory.rawValue {
        case "public.app-category.action-games":
            self.init(key: "appCategory", enum: "actionGames")
        case "public.app-category.adventure-games":
            self.init(key: "appCategory", enum: "adventureGames")
        case "public.app-category.arcade-games":
            self.init(key: "appCategory", enum: "arcadeGames")
        case "public.app-category.board-games":
            self.init(key: "appCategory", enum: "boardGames")
        case "public.app-category.business":
            self.init(key: "appCategory", enum: "business")
        case "public.app-category.card-games":
            self.init(key: "appCategory", enum: "cardGames")
        case "public.app-category.casino-games":
            self.init(key: "appCategory", enum: "casinoGames")
        case "public.app-category.developer-tools":
            self.init(key: "appCategory", enum: "developerTools")
        case "public.app-category.dice-games":
            self.init(key: "appCategory", enum: "diceGames")
        case "public.app-category.education":
            self.init(key: "appCategory", enum: "education")
        case "public.app-category.educational-games":
            self.init(key: "appCategory", enum: "educationalGames")
        case "public.app-category.entertainment":
            self.init(key: "appCategory", enum: "entertainment")
        case "public.app-category.family-games":
            self.init(key: "appCategory", enum: "familyGames")
        case "public.app-category.finance":
            self.init(key: "appCategory", enum: "finance")
        case "public.app-category.games":
            self.init(key: "appCategory", enum: "games")
        case "public.app-category.graphics-design":
            self.init(key: "appCategory", enum: "graphicsDesign")
        case "public.app-category.healthcare-fitness":
            self.init(key: "appCategory", enum: "healthcareFitness")
        case "public.app-category.kids-games":
            self.init(key: "appCategory", enum: "kidsGames")
        case "public.app-category.lifestyle":
            self.init(key: "appCategory", enum: "lifestyle")
        case "public.app-category.medical":
            self.init(key: "appCategory", enum: "medical")
        case "public.app-category.music":
            self.init(key: "appCategory", enum: "music")
        case "public.app-category.music-games":
            self.init(key: "appCategory", enum: "musicGames")
        case "public.app-category.news":
            self.init(key: "appCategory", enum: "news")
        case "public.app-category.photography":
            self.init(key: "appCategory", enum: "photography")
        case "public.app-category.productivity":
            self.init(key: "appCategory", enum: "productivity")
        case "public.app-category.puzzle-games":
            self.init(key: "appCategory", enum: "puzzleGames")
        case "public.app-category.racing-games":
            self.init(key: "appCategory", enum: "racingGames")
        case "public.app-category.reference":
            self.init(key: "appCategory", enum: "reference")
        case "public.app-category.role-playing-games":
            self.init(key: "appCategory", enum: "rolePlayingGames")
        case "public.app-category.simulation-games":
            self.init(key: "appCategory", enum: "simulationGames")
        case "public.app-category.social-networking":
            self.init(key: "appCategory", enum: "socialNetworking")
        case "public.app-category.sports":
            self.init(key: "appCategory", enum: "sports")
        case "public.app-category.sports-games":
            self.init(key: "appCategory", enum: "sportsGames")
        case "public.app-category.strategy-games":
            self.init(key: "appCategory", enum: "strategyGames")
        case "public.app-category.travel":
            self.init(key: "appCategory", enum: "travel")
        case "public.app-category.trivia-games":
            self.init(key: "appCategory", enum: "triviaGames")
        case "public.app-category.utilities":
            self.init(key: "appCategory", enum: "utilities")
        case "public.app-category.video":
            self.init(key: "appCategory", enum: "video")
        case "public.app-category.weather":
            self.init(key: "appCategory", enum: "weather")
        case "public.app-category.word-games":
            self.init(key: "appCategory", enum: "wordGames")
        default:
            self.init(key: "appCategory", string: appCategory.rawValue)
        }
    }
}


/// Convenience initializers for key-value pairs of simple types.  These make
/// the logic above much simpler.
public extension SourceCodeFragment {
    
    /// Initializes a SourceCodeFragment for a boolean in a generated manifest.
    init(key: String? = nil, boolean: Bool) {
        let prefix = key.map{ $0 + ": " } ?? ""
        self.init(prefix + (boolean ? "true" : "false"))
    }

    /// Initializes a SourceCodeFragment for an integer in a generated manifest.
    init(key: String? = nil, integer: Int) {
        let prefix = key.map{ $0 + ": " } ?? ""
        self.init(prefix + "\(integer)")
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

    /// Initializes a SourceCodeFragment for a string map in a generated manifest.
    init(key: String? = nil, stringPairs: [(String, String)], multiline: Bool = false) {
        let prefix = key.map{ $0 + ": " } ?? ""
        let subnodes = stringPairs.isEmpty ? [SourceCodeFragment(":")] : stringPairs.map{ SourceCodeFragment($0.quotedForPackageManifest + ": " + $1.quotedForPackageManifest) }
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


/// Helper type to emit source code.  Represents one node of source code, as an
/// arbitrary string followed by an optional child list, optionally enclosed in
/// a pair of delimiters.
///
/// The source code generation works by creating SourceCodeFragments, and then
/// rendering them into string form with appropriate formatting.
public struct SourceCodeFragment {
    /// A literal prefix to emit at the start of the source code fragment.
    var literal: String
    
    /// The type of delimiters to use around the subfragments (if any).
    var delimiters: Delimiters
    
    /// Whether or not to emit newlines before the subfragments (if any).
    var multiline: Bool
    
    /// Any subfragments; no delimiters are emitted if none.
    var subnodes: [SourceCodeFragment]?
    
    /// Type of delimiters to emit around any subfragments.
    public enum Delimiters {
        case none
        case brackets
        case parentheses
    }
    
    public init(_ literal: String, delimiters: Delimiters = .none,
         multiline: Bool = true, subnodes: [SourceCodeFragment]? = nil) {
        self.literal = literal
        self.delimiters = delimiters
        self.multiline = multiline
        self.subnodes = subnodes
    }
    
    func generateSourceCode(indent: String = "") -> String {
        var string = literal
        if let subnodes {
            switch delimiters {
            case .none: break
            case .brackets: string.append("[")
            case .parentheses: string.append("(")
            }
            if multiline { string.append("\n") }
            let subindent = indent + (multiline ? "    " : "")
            for (idx, subnode) in subnodes.enumerated() {
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

extension TargetBuildSettingDescription.Kind {
    fileprivate var name: String {
        switch self {
        case .headerSearchPath:
            return "headerSearchPath"
        case .define:
            return "define"
        case .linkedLibrary:
            return "linkedLibrary"
        case .linkedFramework:
            return "linkedFramework"
        case .unsafeFlags:
            return "unsafeFlags"
        case .interoperabilityMode:
            return "interoperabilityMode"
        case .enableUpcomingFeature:
            return "enableUpcomingFeature"
        case .enableExperimentalFeature:
            return "enableExperimentalFeature"
        case .strictMemorySafety:
            return "strictMemorySafety"
        case .swiftLanguageMode:
            return "swiftLanguageMode"
        case .defaultIsolation:
            return "defaultIsolation"
        }
    }
}

extension String {
    fileprivate var quotedForPackageManifest: String {
        return "\"" + self
            .replacing("\\", with: "\\\\")
            .replacing("\"", with: "\\\"")
            + "\""
    }
}
