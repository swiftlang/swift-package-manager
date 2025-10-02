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

extension Serialization.BuildConfiguration {
    init(_ configuration: PackageDescription.BuildConfiguration) {
        self.config = configuration.config
    }
}

extension Serialization.BuildSettingCondition {
    init(_ condition: PackageDescription.BuildSettingCondition) {
        self.platforms = condition.platforms?.map { .init($0) }
        self.config = condition.config.map { .init($0) }
        self.traits = condition.traits
    }
}

extension Serialization.BuildSettingData {
    init(_ settingsData: PackageDescription.BuildSettingData) {
        self.name = settingsData.name
        self.value = settingsData.value
        self.condition = settingsData.condition.map { .init($0) }
    }
}

extension Serialization.CSetting {
    init(_ setting: PackageDescription.CSetting) {
        self.data = .init(setting.data)
    }
}

extension Serialization.CXXSetting {
    init(_ setting: PackageDescription.CXXSetting) {
        self.data = .init(setting.data)
    }
}

extension Serialization.SwiftSetting {
    init(_ setting: PackageDescription.SwiftSetting) {
        self.data = .init(setting.data)
    }
}

extension Serialization.LinkerSetting {
    init(_ setting: PackageDescription.LinkerSetting) {
        self.data = .init(setting.data)
    }
}

extension Serialization.CLanguageStandard {
    init(_ languageStandard: PackageDescription.CLanguageStandard) {
        switch languageStandard {
        case .c89: self = .c89
        case .c90: self = .c90
        case .c99: self = .c99
        case .c11: self = .c11
        case .c17: self = .c17
        case .c18: self = .c18
        case .c2x: self = .c2x
        case .gnu89: self = .gnu89
        case .gnu90: self = .gnu90
        case .gnu99: self = .gnu99
        case .gnu11: self = .gnu11
        case .gnu17: self = .gnu17
        case .gnu18: self = .gnu18
        case .gnu2x: self = .gnu2x
        case .iso9899_1990: self = .iso9899_1990
        case .iso9899_199409: self = .iso9899_199409
        case .iso9899_1999: self = .iso9899_1999
        case .iso9899_2011: self = .iso9899_2011
        case .iso9899_2017: self = .iso9899_2017
        case .iso9899_2018: self = .iso9899_2018
        }
    }
}

extension Serialization.CXXLanguageStandard {
    init(_ languageStandard: PackageDescription.CXXLanguageStandard) {
        switch languageStandard {
        case .cxx98: self = .cxx98
        case .cxx03: self = .cxx03
        case .cxx11: self = .cxx11
        case .cxx14: self = .cxx14
        case .cxx17: self = .cxx17
        case .cxx1z: self = .cxx1z
        case .cxx20: self = .cxx20
        case .cxx2b: self = .cxx2b
        case .gnucxx98: self = .gnucxx98
        case .gnucxx03: self = .gnucxx03
        case .gnucxx11: self = .gnucxx11
        case .gnucxx14: self = .gnucxx14
        case .gnucxx17: self = .gnucxx17
        case .gnucxx1z: self = .gnucxx1z
        case .gnucxx20: self = .gnucxx20
        case .gnucxx2b: self = .gnucxx2b
        }
    }
}

extension Serialization.SwiftVersion {
    init(_ swiftVersion: PackageDescription.SwiftLanguageMode) {
        switch swiftVersion {
        case .v3: self = .v3
        case .v4: self = .v4
        case .v4_2: self = .v4_2
        case .v5: self = .v5
        case .v6: self = .v6
        case .version(let version): self = .version(version)
        }
    }
}

extension Serialization.Version {
    init(_ version: PackageDescription.Version) {
        self.major = version.major
        self.minor = version.minor
        self.patch = version.patch
        self.prereleaseIdentifiers = version.prereleaseIdentifiers
        self.buildMetadataIdentifiers = version.buildMetadataIdentifiers
    }
}

extension Serialization.PackageDependency.SourceControlRequirement {
    init(_ requirement: PackageDescription.Package.Dependency.SourceControlRequirement) {
        switch requirement {
        case .range(let range):
            self = .range(lowerBound: .init(range.lowerBound), upperBound: .init(range.upperBound))
        case .exact(let version):
            self = .exact(.init(version))
        case .revision(let revision):
            self = .revision(revision)
        case .branch(let branch):
            self = .branch(branch)
        }
    }
}

extension Serialization.PackageDependency.RegistryRequirement {
    init(_ requirement: PackageDescription.Package.Dependency.RegistryRequirement) {
        switch requirement {
        case .exact(let version):
            self = .exact(.init(version))
        case .range(let range):
            self = .range(lowerBound: .init(range.lowerBound), upperBound: .init(range.upperBound))
        }
    }
}

extension Serialization.PackageDependency.Kind {
    init(_ kind: PackageDescription.Package.Dependency.Kind) {
        switch kind {
        case .fileSystem(let name, let path):
            self = .fileSystem(name: name, path: path)
        case .sourceControl(let name, let location, let requirement):
            self = .sourceControl(name: name, location: location, requirement: .init(requirement))
        case .registry(let identity, let requirement):
            self = .registry(id: identity, requirement: .init(requirement))
        }
    }
}

extension Serialization.PackageDependency {
    init(_ dependency: PackageDescription.Package.Dependency) {
        self.kind = .init(dependency.kind)
        self.moduleAliases = dependency.moduleAliases
        self.traits = Set(dependency.traits.map { Serialization.PackageDependency.Trait.init($0) })
    }
}

extension Serialization.PackageDependency.Trait {
    init(_ trait: PackageDescription.Package.Dependency.Trait) {
        self.name = trait.name
        self.condition = trait.condition.flatMap { .init($0) }
    }
}

extension Serialization.PackageDependency.Trait.Condition {
    init(_ condition: PackageDescription.Package.Dependency.Trait.Condition) {
        self.traits = condition.traits
    }
}

extension Serialization.Platform {
    init(_ platform: PackageDescription.Platform) {
        self.name = platform.name
    }
}

extension Serialization.SupportedPlatform {
    init(_ platform: PackageDescription.SupportedPlatform) {
        self.platform = .init(platform.platform)
        self.version = platform.version
    }
}

extension Serialization.TargetDependency.Condition {
    init(_ condition: TargetDependencyCondition) {
        self.platforms = condition.platforms?.map { .init($0) }
        self.traits = condition.traits
    }
}

extension Serialization.TargetDependency {
    init(_ dependency: PackageDescription.Target.Dependency) {
        switch dependency {
        case .targetItem(let name, let condition):
            self = .target(name: name, condition: condition.map { .init($0) })
        case .productItem(let name, let package, let moduleAliases, let condition):
            self = .product(
                name: name,
                package: package,
                moduleAliases: moduleAliases,
                condition: condition.map { .init($0) }
            )
        case .byNameItem(let name, let condition):
            self = .byName(name: name, condition: condition.map { .init($0) })
        }
    }
}

extension Serialization.TargetType {
    init(_ type: PackageDescription.Target.TargetType) {
        switch type {
        case .regular: self = .regular
        case .executable: self = .executable
        case .test: self = .test
        case .system: self = .system
        case .binary: self = .binary
        case .plugin: self = .plugin
        case .macro: self = .macro
        }
    }
}

extension Serialization.PluginCapability {
    init(_ capability: PackageDescription.Target.PluginCapability) {
        switch capability {
        case .buildTool: self = .buildTool
        case .command(let intent, let permissions): self = .command(
                intent: .init(intent),
                permissions: permissions.map { .init($0) }
            )
        }
    }
}

extension Serialization.PluginCommandIntent {
    init(_ intent: PackageDescription.PluginCommandIntent) {
        switch intent {
        case .custom(let verb, let description): self = .custom(verb: verb, description: description)
        case .sourceCodeFormatting: self = .sourceCodeFormatting
        case .documentationGeneration: self = .documentationGeneration
        }
    }
}

extension Serialization.PluginPermission {
    init(_ permission: PackageDescription.PluginPermission) {
        switch permission {
        case .allowNetworkConnections(let scope, let reason): self = .allowNetworkConnections(
                scope: .init(scope),
                reason: reason
            )
        case .writeToPackageDirectory(let reason): self = .writeToPackageDirectory(reason: reason)
        }
    }
}

extension Serialization.PluginNetworkPermissionScope {
    init(_ scope: PackageDescription.PluginNetworkPermissionScope) {
        switch scope {
        case .none: self = .none
        case .local(let ports): self = .local(ports: ports)
        case .all(let ports): self = .all(ports: ports)
        case .docker: self = .docker
        case .unixDomainSocket: self = .unixDomainSocket
        }
    }
}

extension Serialization.PluginUsage {
    init(_ usage: PackageDescription.Target.PluginUsage) {
        switch usage {
        case .plugin(let name, let package): self = .plugin(name: name, package: package)
        }
    }
}

extension Serialization.Target {
    init(_ target: PackageDescription.Target) {
        self.name = target.name
        self.packageAccess = target.packageAccess
        self.path = target.path
        self.url = target.url
        self.sources = target.sources
        self.resources = target.resources?.map { .init($0) }
        self.exclude = target.exclude
        self.dependencies = target.dependencies.map { .init($0) }
        self.publicHeadersPath = target.publicHeadersPath
        self.type = .init(target.type)
        self.pkgConfig = target.pkgConfig
        self.providers = target.providers?.map { .init($0) }
        self.pluginCapability = target.pluginCapability.map { .init($0) }
        self.cSettings = target.cSettings?.map { .init($0) }
        self.cxxSettings = target.cxxSettings?.map { .init($0) }
        self.swiftSettings = target.swiftSettings?.map { .init($0) }
        self.linkerSettings = target.linkerSettings?.map { .init($0) }
        self.checksum = target.checksum
        self.pluginUsages = target.plugins?.map { .init($0) }
    }
}

extension Serialization.Resource {
    init(_ resource: PackageDescription.Resource) {
        self.rule = resource.rule
        self.path = resource.path
        self.localization = resource.localization.map { .init($0) }
    }
}

extension Serialization.Resource.Localization {
    init(_ localization: PackageDescription.Resource.Localization) {
        switch localization {
        case .base: self = .base
        case .default: self = .default
        }
    }
}

extension Serialization.Product.ProductType.LibraryType {
    init(_ type: PackageDescription.Product.Library.LibraryType) {
        switch type {
        case .dynamic: self = .dynamic
        case .static: self = .static
        }
    }
}

extension Serialization.Product {
    init(_ product: PackageDescription.Product) {
        if let executable = product as? PackageDescription.Product.Executable {
            self.init(executable)
        } else if let library = product as? PackageDescription.Product.Library {
            self.init(library)
        } else if let plugin = product as? PackageDescription.Product.Plugin {
            self.init(plugin)
        } else {
            fatalError("should not be reached")
        }
    }

    init(_ executable: PackageDescription.Product.Executable) {
        self.name = executable.name
        self.targets = executable.targets
        self.productType = .executable
        #if ENABLE_APPLE_PRODUCT_TYPES
        self.settings = executable.settings.map { .init($0) }
        #endif
    }

    init(_ library: PackageDescription.Product.Library) {
        self.name = library.name
        self.targets = library.targets
        let libraryType = library.type.map { ProductType.LibraryType($0) } ?? .automatic
        self.productType = .library(type: libraryType)
        #if ENABLE_APPLE_PRODUCT_TYPES
        self.settings = []
        #endif
    }

    init(_ plugin: PackageDescription.Product.Plugin) {
        self.name = plugin.name
        self.targets = plugin.targets
        self.productType = .plugin
        #if ENABLE_APPLE_PRODUCT_TYPES
        self.settings = []
        #endif
    }
}

extension Serialization.Trait {
    init(_ trait: PackageDescription.Trait) {
        self.name = trait.name
        self.description = trait.description
        self.enabledTraits = trait.enabledTraits
    }
}

extension Serialization.Package {
    init(_ package: PackageDescription.Package) {
        self.name = package.name
        self.platforms = package.platforms?.map { .init($0) }
        self.defaultLocalization = package.defaultLocalization.map { .init($0) }
        self.pkgConfig = package.pkgConfig
        self.providers = package.providers?.map { .init($0) }
        self.targets = package.targets.map { .init($0) }
        self.products = package.products.map { .init($0) }
        self.traits = Set(package.traits.map { Serialization.Trait($0) })
        self.dependencies = package.dependencies.map { .init($0) }
        self.swiftLanguageVersions = package.swiftLanguageModes?.map { .init($0) }
        self.cLanguageStandard = package.cLanguageStandard.map { .init($0) }
        self.cxxLanguageStandard = package.cxxLanguageStandard.map { .init($0) }
    }
}

extension Serialization.LanguageTag {
    init(_ language: PackageDescription.LanguageTag) {
        self.tag = language.tag
    }
}

extension Serialization.SystemPackageProvider {
    init(_ provider: PackageDescription.SystemPackageProvider) {
        switch provider {
        case .brewItem(let values): self = .brew(values)
        case .aptItem(let values): self = .apt(values)
        case .yumItem(let values): self = .yum(values)
        case .nugetItem(let values): self = .nuget(values)
        }
    }
}

#if ENABLE_APPLE_PRODUCT_TYPES
extension Serialization.ProductSetting {
    init(_ setting: PackageDescription.ProductSetting) {
        switch setting {
        case .bundleIdentifier(let value):
            self = .bundleIdentifier(value)
        case .teamIdentifier(let value):
            self = .teamIdentifier(value)
        case .displayVersion(let value):
            self = .displayVersion(value)
        case .bundleVersion(let value):
            self = .bundleVersion(value)
        case .iOSAppInfo(let appInfo):
            self = .iOSAppInfo(.init(appInfo))
        }
    }
}

extension Serialization.ProductSetting.IOSAppInfo {
    init(_ appInfo: PackageDescription.ProductSetting.IOSAppInfo) {
        self.init(
            appIcon: appInfo.appIcon.map { .init($0) },
            accentColor: appInfo.accentColor.map { .init($0) },
            supportedDeviceFamilies: appInfo.supportedDeviceFamilies.map { .init($0) },
            supportedInterfaceOrientations: appInfo.supportedInterfaceOrientations.map { .init($0) },
            capabilities: appInfo.capabilities.map { .init($0) },
            appCategory: appInfo.appCategory.map { .init($0) },
            additionalInfoPlistContentFilePath: appInfo.additionalInfoPlistContentFilePath
        )
    }
}

extension Serialization.ProductSetting.IOSAppInfo.AccentColor {
    init(_ color: PackageDescription.ProductSetting.IOSAppInfo.AccentColor) {
        switch color {
        case .presetColor(let color):
            self = .presetColor(.init(color))
        case .asset(let value):
            self = .asset(value)
        }
    }
}

extension Serialization.ProductSetting.IOSAppInfo.AccentColor.PresetColor {
    init(_ color: PackageDescription.ProductSetting.IOSAppInfo.AccentColor.PresetColor) {
        self.rawValue = color.rawValue
    }
}

extension Serialization.ProductSetting.IOSAppInfo.AppIcon {
    init(_ icon: PackageDescription.ProductSetting.IOSAppInfo.AppIcon) {
        switch icon {
        case .placeholder(icon: let icon):
            self = .placeholder(icon: .init(icon))
        case .asset(let value):
            self = .asset(value)
        }
    }
}

extension Serialization.ProductSetting.IOSAppInfo.AppIcon.PlaceholderIcon {
    init(_ icon: PackageDescription.ProductSetting.IOSAppInfo.AppIcon.PlaceholderIcon) {
        self.rawValue = icon.rawValue
    }
}

extension Serialization.ProductSetting.IOSAppInfo.DeviceFamily {
    init(_ deviceFamily: PackageDescription.ProductSetting.IOSAppInfo.DeviceFamily) {
        switch deviceFamily {
        case .phone: self = .phone
        case .pad: self = .pad
        case .mac: self = .mac
        }
    }
}

extension Serialization.ProductSetting.IOSAppInfo.DeviceFamilyCondition {
    init(_ condition: PackageDescription.ProductSetting.IOSAppInfo.DeviceFamilyCondition) {
        self.init(deviceFamilies: condition.deviceFamilies.map { .init($0) })
    }
}

extension Serialization.ProductSetting.IOSAppInfo.InterfaceOrientation {
    init(_ interfaceOrientation: PackageDescription.ProductSetting.IOSAppInfo.InterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait(let condition):
            self = .portrait(condition.map { .init($0) })
        case .portraitUpsideDown(let condition):
            self = .portraitUpsideDown(condition.map { .init($0) })
        case .landscapeRight(let condition):
            self = .landscapeRight(condition.map { .init($0) })
        case .landscapeLeft(let condition):
            self = .landscapeLeft(condition.map { .init($0) })
        }
    }
}

extension Serialization.ProductSetting.IOSAppInfo.Capability {
    init(_ capability: PackageDescription.ProductSetting.IOSAppInfo.Capability) {
        switch capability {
        case .appTransportSecurity(configuration: let configuration, let condition):
            self = .appTransportSecurity(configuration: .init(configuration), condition.map { .init($0) })
        case .bluetoothAlways(purposeString: let purposeString, let condition):
            self = .bluetoothAlways(purposeString: purposeString, condition.map { .init($0) })
        case .calendars(purposeString: let purposeString, let condition):
            self = .calendars(purposeString: purposeString, condition.map { .init($0) })
        case .camera(purposeString: let purposeString, let condition):
            self = .camera(purposeString: purposeString, condition.map { .init($0) })
        case .contacts(purposeString: let purposeString, let condition):
            self = .contacts(purposeString: purposeString, condition.map { .init($0) })
        case .faceID(purposeString: let purposeString, let condition):
            self = .faceID(purposeString: purposeString, condition.map { .init($0) })
        case .fileAccess(let location, let mode, let condition):
            self = .fileAccess(.init(location), mode: .init(mode), condition.map { .init($0) })
        case .incomingNetworkConnections(let condition):
            self = .incomingNetworkConnections(condition.map { .init($0) })
        case .localNetwork(purposeString: let purposeString, bonjourServiceTypes: let bonjourServiceTypes, let condition):
            self = .localNetwork(purposeString: purposeString, bonjourServiceTypes: bonjourServiceTypes, condition.map { .init($0) })
        case .locationAlwaysAndWhenInUse(purposeString: let purposeString, let condition):
            self = .locationAlwaysAndWhenInUse(purposeString: purposeString, condition.map { .init($0) })
        case .locationWhenInUse(purposeString: let purposeString, let condition):
            self = .locationWhenInUse(purposeString: purposeString, condition.map { .init($0) })
        case .mediaLibrary(purposeString: let purposeString, let condition):
            self = .mediaLibrary(purposeString: purposeString, condition.map { .init($0) })
        case .microphone(purposeString: let purposeString, let condition):
            self = .microphone(purposeString: purposeString, condition.map { .init($0) })
        case .motion(purposeString: let purposeString, let condition):
            self = .motion(purposeString: purposeString, condition.map { .init($0) })
        case .nearbyInteractionAllowOnce(purposeString: let purposeString, let condition):
            self = .nearbyInteractionAllowOnce(purposeString: purposeString, condition.map { .init($0) })
        case .outgoingNetworkConnections(let condition):
            self = .outgoingNetworkConnections(condition.map { .init($0) })
        case .photoLibrary(purposeString: let purposeString, let condition):
            self = .photoLibrary(purposeString: purposeString, condition.map { .init($0) })
        case .photoLibraryAdd(purposeString: let purposeString, let condition):
            self = .photoLibraryAdd(purposeString: purposeString, condition.map { .init($0) })
        case .reminders(purposeString: let purposeString, let condition):
            self = .reminders(purposeString: purposeString, condition.map { .init($0) })
        case .speechRecognition(purposeString: let purposeString, let condition):
            self = .speechRecognition(purposeString: purposeString, condition.map { .init($0) })
        case .userTracking(purposeString: let purposeString, let condition):
            self = .userTracking(purposeString: purposeString, condition.map { .init($0) })
        }
    }
}

extension Serialization.ProductSetting.IOSAppInfo.AppTransportSecurityConfiguration {
    init(_ configuration: PackageDescription.ProductSetting.IOSAppInfo.AppTransportSecurityConfiguration) {
        self.init(
            allowsArbitraryLoadsInWebContent: configuration.allowsArbitraryLoadsInWebContent,
            allowsArbitraryLoadsForMedia: configuration.allowsArbitraryLoadsForMedia,
            allowsLocalNetworking: configuration.allowsLocalNetworking,
            exceptionDomains: configuration.exceptionDomains?.map { .init($0) },
            pinnedDomains: configuration.pinnedDomains?.map { .init($0) }
        )
    }
}

extension Serialization.ProductSetting.IOSAppInfo.AppTransportSecurityConfiguration.ExceptionDomain {
    init(_ exceptionDomain: PackageDescription.ProductSetting.IOSAppInfo.AppTransportSecurityConfiguration.ExceptionDomain) {
        self.init(
            domainName: exceptionDomain.domainName,
            includesSubdomains: exceptionDomain.includesSubdomains,
            exceptionAllowsInsecureHTTPLoads: exceptionDomain.exceptionAllowsInsecureHTTPLoads,
            exceptionMinimumTLSVersion: exceptionDomain.exceptionMinimumTLSVersion,
            exceptionRequiresForwardSecrecy: exceptionDomain.exceptionRequiresForwardSecrecy,
            requiresCertificateTransparency: exceptionDomain.requiresCertificateTransparency
        )
    }
}

extension Serialization.ProductSetting.IOSAppInfo.AppTransportSecurityConfiguration.PinnedDomain {
    init(_ pinnedDomain: PackageDescription.ProductSetting.IOSAppInfo.AppTransportSecurityConfiguration.PinnedDomain) {
        self.init(
            domainName: pinnedDomain.domainName,
            includesSubdomains: pinnedDomain.includesSubdomains,
            pinnedCAIdentities: pinnedDomain.pinnedCAIdentities,
            pinnedLeafIdentities: pinnedDomain.pinnedLeafIdentities
        )
    }
}

extension Serialization.ProductSetting.IOSAppInfo.FileAccessLocation {
    init(_ fileAccessLocation: PackageDescription.ProductSetting.IOSAppInfo.FileAccessLocation) {
        switch fileAccessLocation {
        case .userSelectedFiles: self = .userSelectedFiles
        case .downloadsFolder: self = .downloadsFolder
        case .pictureFolder: self = .pictureFolder
        case .musicFolder: self = .musicFolder
        case .moviesFolder: self = .moviesFolder
        }
    }
}

extension Serialization.ProductSetting.IOSAppInfo.FileAccessMode {
    init(_ fileAccessNode: PackageDescription.ProductSetting.IOSAppInfo.FileAccessMode) {
        switch fileAccessNode {
        case .readOnly: self = .readOnly
        case .readWrite: self = .readWrite
        }
    }
}

extension Serialization.ProductSetting.IOSAppInfo.AppCategory {
    init(_ appCategory: PackageDescription.ProductSetting.IOSAppInfo.AppCategory) {
        self.rawValue = appCategory.rawValue
    }
}
#endif
