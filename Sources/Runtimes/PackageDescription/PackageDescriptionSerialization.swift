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

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import Foundation
#else
import Foundation
#endif

enum Serialization {
    // MARK: - build settings serialization

    struct BuildConfiguration: Codable {
        let config: String
    }

    struct BuildSettingCondition: Codable {
        let platforms: [Platform]?
        let config: BuildConfiguration?
        let traits: Set<String>?
    }

    struct BuildSettingData: Codable {
        let name: String
        let value: [String]
        let condition: BuildSettingCondition?
    }

    struct CSetting: Codable {
        let data: BuildSettingData
    }

    struct CXXSetting: Codable {
        let data: BuildSettingData
    }

    struct SwiftSetting: Codable {
        let data: BuildSettingData
    }

    struct LinkerSetting: Codable {
        let data: BuildSettingData
    }

    // MARK: - language standards serialization

    enum CLanguageStandard: String, Codable {
        case c89
        case c90
        case c99
        case c11
        case c17
        case c18
        case c2x
        case gnu89
        case gnu90
        case gnu99
        case gnu11
        case gnu17
        case gnu18
        case gnu2x
        case iso9899_1990 = "iso9899:1990"
        case iso9899_199409 = "iso9899:199409"
        case iso9899_1999 = "iso9899:1999"
        case iso9899_2011 = "iso9899:2011"
        case iso9899_2017 = "iso9899:2017"
        case iso9899_2018 = "iso9899:2018"
    }

    enum CXXLanguageStandard: String, Codable {
        case cxx98 = "c++98"
        case cxx03 = "c++03"
        case cxx11 = "c++11"
        case cxx14 = "c++14"
        case cxx17 = "c++17"
        case cxx1z = "c++1z"
        case cxx20 = "c++20"
        case cxx2b = "c++2b"
        case gnucxx98 = "gnu++98"
        case gnucxx03 = "gnu++03"
        case gnucxx11 = "gnu++11"
        case gnucxx14 = "gnu++14"
        case gnucxx17 = "gnu++17"
        case gnucxx1z = "gnu++1z"
        case gnucxx20 = "gnu++20"
        case gnucxx2b = "gnu++2b"
    }

    enum SwiftVersion: Codable {
        case v3
        case v4
        case v4_2
        case v5
        case v6
        case version(String)
    }

    // MARK: - version serialization

    struct Version: Codable {
        let major: Int
        let minor: Int
        let patch: Int
        let prereleaseIdentifiers: [String]
        let buildMetadataIdentifiers: [String]
    }

    // MARK: - package dependency serialization

    struct PackageDependency: Codable {
        struct Trait: Hashable, Codable {
            struct Condition: Hashable, Codable {
                let traits: Set<String>?
            }

            var name: String
            var condition: Condition?
        }
        enum SourceControlRequirement: Codable {
            case exact(Version)
            case range(lowerBound: Version, upperBound: Version)
            case revision(String)
            case branch(String)
        }

        enum RegistryRequirement: Codable {
            case exact(Version)
            case range(lowerBound: Version, upperBound: Version)
        }

        enum Kind: Codable {
            case fileSystem(name: String?, path: String)
            case sourceControl(name: String?, location: String, requirement: SourceControlRequirement)
            case registry(id: String, requirement: RegistryRequirement)
        }

        let kind: Kind
        let moduleAliases: [String: String]?
        let traits: Set<Trait>?
    }

    // MARK: - platforms serialization

    struct Platform: Codable {
        let name: String
    }

    struct SupportedPlatform: Codable {
        let platform: Platform
        let version: String?
    }

    // MARK: - target serialization

    enum TargetDependency: Codable {
        struct Condition: Codable {
            let platforms: [Platform]?
            let traits: Set<String>?
        }

        case target(name: String, condition: Condition?)
        case product(name: String, package: String?, moduleAliases: [String: String]?, condition: Condition?)
        case byName(name: String, condition: Condition?)
    }

    enum TargetType: Codable {
        case regular
        case executable
        case test
        case system
        case binary
        case plugin
        case `macro`
    }

    enum PluginCapability: Codable {
        case buildTool
        case command(intent: PluginCommandIntent, permissions: [PluginPermission])
    }

    enum PluginCommandIntent: Codable {
        case documentationGeneration
        case sourceCodeFormatting
        case custom(verb: String, description: String)
    }

    enum PluginPermission: Codable {
        case allowNetworkConnections(scope: PluginNetworkPermissionScope, reason: String)
        case writeToPackageDirectory(reason: String)
    }

    enum PluginNetworkPermissionScope: Codable {
        case none
        case local(ports: [Int])
        case all(ports: [Int])
        case docker
        case unixDomainSocket
    }

    enum PluginUsage: Codable {
        case plugin(name: String, package: String?)
    }

    struct Target: Codable {
        let name: String
        let path: String?
        let url: String?
        let sources: [String]?
        let resources: [Resource]?
        let exclude: [String]
        let dependencies: [TargetDependency]
        let publicHeadersPath: String?
        let type: TargetType
        let packageAccess: Bool
        let pkgConfig: String?
        let providers: [SystemPackageProvider]?
        let pluginCapability: PluginCapability?
        let cSettings: [CSetting]?
        let cxxSettings: [CXXSetting]?
        let swiftSettings: [SwiftSetting]?
        let linkerSettings: [LinkerSetting]?
        let checksum: String?
        let pluginUsages: [PluginUsage]?
    }

    // MARK: - resource serialization

    struct Resource: Codable {
        enum Localization: String, Codable {
            case `default`
            case base
        }

        let rule: String
        let path: String
        let localization: Localization?
    }

    // MARK: - product serialization

    struct Product: Codable {
        enum ProductType: Codable {
            enum LibraryType: Codable {
                case automatic
                case dynamic
                case `static`
            }

            case executable
            case library(type: LibraryType)
            case plugin
        }

        let name: String
        let targets: [String]
        let productType: ProductType

        #if ENABLE_APPLE_PRODUCT_TYPES
        let settings: [ProductSetting]
        #endif
    }

    // MARK: - trait serialization

    struct Trait: Hashable, Codable {
        let name: String
        let description: String?
        let enabledTraits: Set<String>
    }

    // MARK: - package serialization

    struct LanguageTag: Codable {
        let tag: String
    }

    enum SystemPackageProvider: Codable {
        case brew([String])
        case apt([String])
        case yum([String])
        case nuget([String])
    }

    struct Package: Codable {
        let name: String
        let platforms: [SupportedPlatform]?
        let defaultLocalization: LanguageTag?
        let pkgConfig: String?
        let providers: [SystemPackageProvider]?
        let targets: [Target]
        let products: [Product]
        let traits: Set<Trait>?
        let dependencies: [PackageDependency]
        let swiftLanguageVersions: [SwiftVersion]?
        let cLanguageStandard: CLanguageStandard?
        let cxxLanguageStandard: CXXLanguageStandard?
    }
}

#if ENABLE_APPLE_PRODUCT_TYPES
extension Serialization {
    enum ProductSetting: Codable {
        case bundleIdentifier(String)
        case teamIdentifier(String)
        case displayVersion(String)
        case bundleVersion(String)
        case iOSAppInfo(IOSAppInfo)
        
        struct IOSAppInfo: Codable {
            var appIcon: AppIcon?
            var accentColor: AccentColor?
            var supportedDeviceFamilies: [DeviceFamily]
            var supportedInterfaceOrientations: [InterfaceOrientation]
            var capabilities: [Capability] = []
            var appCategory: AppCategory?
            var additionalInfoPlistContentFilePath: String?
            
            enum AccentColor: Codable {
                struct PresetColor: Codable {
                    var rawValue: String
                }
                
                case presetColor(PresetColor)
                case asset(String)
            }
            
            enum AppIcon: Codable {
                struct PlaceholderIcon: Codable {
                    var rawValue: String
                }
                
                case placeholder(icon: PlaceholderIcon)
                case asset(String)
            }
            
            enum DeviceFamily: String, Codable {
                case phone
                case pad
                case mac
            }
            
            struct DeviceFamilyCondition: Codable {
                var deviceFamilies: [DeviceFamily]
            }
            
            enum InterfaceOrientation: Codable {
                case portrait(_ condition: DeviceFamilyCondition? = nil)
                case portraitUpsideDown(_ condition: DeviceFamilyCondition? = nil)
                case landscapeRight(_ condition: DeviceFamilyCondition? = nil)
                case landscapeLeft(_ condition: DeviceFamilyCondition? = nil)
            }
            
            enum Capability: Codable {
                case appTransportSecurity(configuration: AppTransportSecurityConfiguration, _ condition: DeviceFamilyCondition? = nil)
                case bluetoothAlways(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case calendars(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case camera(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case contacts(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case faceID(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case fileAccess(_ location: FileAccessLocation, mode: FileAccessMode, _ condition: DeviceFamilyCondition? = nil)
                case incomingNetworkConnections(_ condition: DeviceFamilyCondition? = nil)
                case localNetwork(purposeString: String, bonjourServiceTypes: [String]? = nil, _ condition: DeviceFamilyCondition? = nil)
                case locationAlwaysAndWhenInUse(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case locationWhenInUse(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case mediaLibrary(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case microphone(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case motion(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case nearbyInteractionAllowOnce(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case outgoingNetworkConnections(_ condition: DeviceFamilyCondition? = nil)
                case photoLibrary(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case photoLibraryAdd(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case reminders(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case speechRecognition(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
                case userTracking(purposeString: String, _ condition: DeviceFamilyCondition? = nil)
            }
            
            struct AppTransportSecurityConfiguration: Codable {
                var allowsArbitraryLoadsInWebContent: Bool? = nil
                var allowsArbitraryLoadsForMedia: Bool? = nil
                var allowsLocalNetworking: Bool? = nil
                var exceptionDomains: [ExceptionDomain]? = nil
                var pinnedDomains: [PinnedDomain]? = nil
                
                struct ExceptionDomain: Codable {
                    var domainName: String
                    var includesSubdomains: Bool? = nil
                    var exceptionAllowsInsecureHTTPLoads: Bool? = nil
                    var exceptionMinimumTLSVersion: String? = nil
                    var exceptionRequiresForwardSecrecy: Bool? = nil
                    var requiresCertificateTransparency: Bool? = nil
                }
                
                struct PinnedDomain: Codable {
                    var domainName: String
                    var includesSubdomains : Bool? = nil
                    var pinnedCAIdentities : [[String: String]]? = nil
                    var pinnedLeafIdentities : [[String: String]]? = nil
                }
            }
            
            enum FileAccessLocation: String, Codable {
                case userSelectedFiles
                case downloadsFolder
                case pictureFolder
                case musicFolder
                case moviesFolder
            }
            
            enum FileAccessMode: String, Codable {
                case readOnly
                case readWrite
            }
            
            struct AppCategory: Codable {
                var rawValue: String
            }
        }
    }
}
#endif
