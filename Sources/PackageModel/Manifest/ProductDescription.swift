//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

/// The product description
public struct ProductDescription: Hashable, Codable, Sendable {

    /// The name of the product.
    public let name: String

    /// The targets in the product.
    public let targets: [String]

    /// The type of product.
    public let type: ProductType

    /// The product-specific settings declared for this product.
    public let settings: [ProductSetting]

    /// The deprecation information declared for the product, if any.
    public let deprecation: ProductDeprecation?

    public init(
        name: String,
        type: ProductType,
        targets: [String],
        settings: [ProductSetting] = [],
        deprecation: ProductDeprecation? = nil,
    ) throws {
        guard type != .test else {
            throw InternalError("Declaring test products isn't supported: \(name):\(targets)")
        }
        self.name = name
        self.type = type
        self.targets = targets
        self.settings = settings
        self.deprecation = deprecation
    }
}

/// The deprecation state of a product declared in a package manifest.
public struct ProductDeprecation: Hashable, Codable, Sendable {
    /// The product a consumer should adopt in place of an unsupported product.
    ///
    /// This enum is non-frozen: additional cases may be introduced in future evolution.
    public enum Replacement: Hashable, Sendable {
        /// The replacement product. When `package` is nil the replacement lives
        /// in the same package as the deprecated product; otherwise it lives in
        /// the named package (which the consumer must already depend on).
        case renamed(_ product: String, package: String? = nil)
    }

    /// An author-supplied human-readable explanation of the deprecation.
    public let message: String?

    /// The product a consumer should adopt in place of the unsupported product.
    public let replacement: Replacement?

    public init(
        message: String?,
        replacement: Replacement?,
    ) {
        self.message = message
        self.replacement = replacement
    }
}

extension ProductDeprecation.Replacement: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case product
        case package
    }

    private enum Kind: String, Codable {
        case renamed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .renamed(let product, let package):
            try container.encode(Kind.renamed, forKey: .kind)
            try container.encode(product, forKey: .product)
            try container.encodeIfPresent(package, forKey: .package)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .renamed:
            self = .renamed(
                try container.decode(String.self, forKey: .product),
                package: try container.decodeIfPresent(String.self, forKey: .package),
            )
        }
    }
}

extension ProductDeprecation.Replacement {
    /// A human-readable sentence pointing the consumer at the replacement,
    /// suitable for appending to a deprecation diagnostic.
    public var formattedInstruction: String {
        switch self {
        case .renamed(let product, nil):
            return "Use '\(product)' instead."
        case .renamed(let product, let package?):
            return "Use '\(product)' from package '\(package)' instead."
        }
    }
}

/// A particular setting to apply to a product. Some may be specific to certain platforms.
public enum ProductSetting: Equatable, Codable, Sendable, Hashable {
    case bundleIdentifier(String)
    case teamIdentifier(String)
    case displayVersion(String)
    case bundleVersion(String)
    case iOSAppInfo(IOSAppInfo)

    public struct IOSAppInfo: Equatable, Codable, Sendable, Hashable {
        public var appIcon: AppIcon?
        public var accentColor: AccentColor?
        public var supportedDeviceFamilies: [DeviceFamily]
        public var supportedInterfaceOrientations: [InterfaceOrientation]
        public var capabilities: [Capability]
        public var appCategory: AppCategory?
        public var additionalInfoPlistContentFilePath: String?

        public enum DeviceFamily: String, Equatable, Codable, Sendable, Hashable {
            case pad
            case phone
            case mac
        }
        
        public struct DeviceFamilyCondition: Equatable, Codable, Sendable, Hashable {
            public let deviceFamilies: [DeviceFamily]
            public init(deviceFamilies: [DeviceFamily]) {
                self.deviceFamilies = deviceFamilies
            }
        }

        public enum InterfaceOrientation: Equatable, Codable, Sendable, Hashable {
            case portrait(condition: DeviceFamilyCondition?)
            case portraitUpsideDown(condition: DeviceFamilyCondition?)
            case landscapeRight(condition: DeviceFamilyCondition?)
            case landscapeLeft(condition: DeviceFamilyCondition?)
        }
        
        public enum AppIcon: Equatable, Codable, Sendable, Hashable {
            public struct PlaceholderIcon: Equatable, Codable, Sendable, Hashable {
                public var rawValue: String

                public init(rawValue: String) {
                    self.rawValue = rawValue
                }
            }

            case placeholder(icon: PlaceholderIcon)
            case asset(name: String)
        }

        public enum AccentColor: Equatable, Codable, Sendable, Hashable {
            public struct PresetColor: Equatable, Codable, Sendable, Hashable {
                public var rawValue: String

                public init(rawValue: String) {
                    self.rawValue = rawValue
                }
            }

            case presetColor(presetColor: PresetColor)
            case asset(name: String)
        }

        public struct Capability: Equatable, Codable, Sendable, Hashable {
            public var purpose: String
            public var purposeString: String?
            public var appTransportSecurityConfiguration: AppTransportSecurityConfiguration?
            public var bonjourServiceTypes: [String]?
            public var fileAccessLocation: String?
            public var fileAccessMode: String?
            public var condition: DeviceFamilyCondition?
            
            public init(
                purpose: String,
                purposeString: String? = nil,
                appTransportSecurityConfiguration: AppTransportSecurityConfiguration? = nil,
                bonjourServiceTypes: [String]? = nil,
                fileAccessLocation: String? = nil,
                fileAccessMode: String? = nil,
                condition: DeviceFamilyCondition?
            ) {
                self.purpose = purpose
                self.purposeString = purposeString
                self.appTransportSecurityConfiguration = appTransportSecurityConfiguration
                self.bonjourServiceTypes = bonjourServiceTypes
                self.fileAccessLocation = fileAccessLocation
                self.fileAccessMode = fileAccessMode
                self.condition = condition
            }
        }
        
        public struct AppTransportSecurityConfiguration: Equatable, Codable, Sendable, Hashable {
            public var allowsArbitraryLoadsInWebContent: Bool? = nil
            public var allowsArbitraryLoadsForMedia: Bool? = nil
            public var allowsLocalNetworking: Bool? = nil
            public var exceptionDomains: [ExceptionDomain]? = nil
            public var pinnedDomains: [PinnedDomain]? = nil

            public struct ExceptionDomain: Equatable, Codable, Sendable, Hashable {
                public var domainName: String
                public var includesSubdomains: Bool? = nil
                public var exceptionAllowsInsecureHTTPLoads: Bool? = nil
                public var exceptionMinimumTLSVersion: String? = nil
                public var exceptionRequiresForwardSecrecy: Bool? = nil
                public var requiresCertificateTransparency: Bool? = nil
                
                public init(
                    domainName: String,
                    includesSubdomains: Bool?,
                    exceptionAllowsInsecureHTTPLoads: Bool?,
                    exceptionMinimumTLSVersion: String?,
                    exceptionRequiresForwardSecrecy: Bool?,
                    requiresCertificateTransparency: Bool?
                ) {
                    self.domainName = domainName
                    self.includesSubdomains = includesSubdomains
                    self.exceptionAllowsInsecureHTTPLoads = exceptionAllowsInsecureHTTPLoads
                    self.exceptionMinimumTLSVersion = exceptionMinimumTLSVersion
                    self.exceptionRequiresForwardSecrecy = exceptionRequiresForwardSecrecy
                    self.requiresCertificateTransparency = requiresCertificateTransparency
                }
            }
            
            public struct PinnedDomain: Equatable, Codable, Sendable, Hashable {
                public var domainName: String
                public var includesSubdomains : Bool? = nil
                public var pinnedCAIdentities : [[String: String]]? = nil
                public var pinnedLeafIdentities : [[String: String]]? = nil
                
                public init(
                    domainName: String,
                    includesSubdomains: Bool?,
                    pinnedCAIdentities : [[String: String]]? ,
                    pinnedLeafIdentities : [[String: String]]?
                ) {
                    self.domainName = domainName
                    self.includesSubdomains = includesSubdomains
                    self.pinnedCAIdentities = pinnedCAIdentities
                    self.pinnedLeafIdentities = pinnedLeafIdentities
                }
            }

            public init(
                allowsArbitraryLoadsInWebContent: Bool?,
                allowsArbitraryLoadsForMedia: Bool?,
                allowsLocalNetworking: Bool?,
                exceptionDomains: [ExceptionDomain]?,
                pinnedDomains: [PinnedDomain]?
            ) {
                self.allowsArbitraryLoadsInWebContent = allowsArbitraryLoadsInWebContent
                self.allowsArbitraryLoadsForMedia = allowsArbitraryLoadsForMedia
                self.allowsLocalNetworking = allowsLocalNetworking
                self.exceptionDomains = exceptionDomains
                self.pinnedDomains = pinnedDomains
            }
        }
        
        public struct AppCategory: Equatable, Codable, Sendable, Hashable {
            public var rawValue: String

            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }

        public init(
            appIcon: AppIcon?,
            accentColor: AccentColor?,
            supportedDeviceFamilies: [DeviceFamily],
            supportedInterfaceOrientations: [InterfaceOrientation],
            capabilities: [Capability],
            appCategory: AppCategory?,
            additionalInfoPlistContentFilePath: String?
        ) {
            self.appIcon = appIcon
            self.accentColor = accentColor
            self.supportedDeviceFamilies = supportedDeviceFamilies
            self.supportedInterfaceOrientations = supportedInterfaceOrientations
            self.capabilities = capabilities
            self.appCategory = appCategory
            self.additionalInfoPlistContentFilePath = additionalInfoPlistContentFilePath
        }
    }
}


extension ProductSetting {
    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case teamIdentifier
        case displayVersion
        case bundleVersion
        case iOSAppInfo
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .bundleIdentifier(value):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .bundleIdentifier)
            try unkeyedContainer.encode(value)
        case let .teamIdentifier(value):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .teamIdentifier)
            try unkeyedContainer.encode(value)
        case let .displayVersion(value):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .displayVersion)
            try unkeyedContainer.encode(value)
        case let .bundleVersion(value):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .bundleVersion)
            try unkeyedContainer.encode(value)
        case let .iOSAppInfo(value):
            var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .iOSAppInfo)
            try unkeyedContainer.encode(value)
        }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = values.allKeys.first(where: values.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
        }
        switch key {
        case .bundleIdentifier:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let value = try unkeyedValues.decode(String.self)
            self = .bundleIdentifier(value)
        case .teamIdentifier:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let value = try unkeyedValues.decode(String.self)
            self = .teamIdentifier(value)
        case .displayVersion:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let value = try unkeyedValues.decode(String.self)
            self = .displayVersion(value)
        case .bundleVersion:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let value = try unkeyedValues.decode(String.self)
            self = .bundleVersion(value)
        case .iOSAppInfo:
            var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
            let value = try unkeyedValues.decode(IOSAppInfo.self)
            self = .iOSAppInfo(value)
        }
    }
}
