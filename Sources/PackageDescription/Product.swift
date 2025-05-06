//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// The object that defines a package product.
///
/// A package product defines an externally visible build artifact that's
/// available to clients of a package. Swift Package Manager assembles the product from the
/// build artifacts of one or more of the package's targets. A package product
/// can be one of three types:
///
/// - term Library: Use a _library product_ to vend library targets. This makes
/// a target's public APIs available to clients that integrate the Swift
/// package.
/// - term Executable: Use an _executable product_ to vend an
/// executable target. Use this only if you want to make the executable
/// available to clients.
/// - term Plugin: Use a _plugin product_ to vend plugin targets. This makes
/// the plugin available to clients that integrate the Swift package.
///
/// The following example shows a package manifest for a library called “Paper”
/// that defines multiple products:
///
/// ```swift
/// let package = Package(
///     name: "Paper",
///     products: [
///         .executable(name: "tool", targets: ["tool"]),
///         .library(name: "Paper", targets: ["Paper"]),
///         .library(name: "PaperStatic", type: .static, targets: ["Paper"]),
///         .library(name: "PaperDynamic", type: .dynamic, targets: ["Paper"]),
///     ],
///     dependencies: [
///         .package(url: "http://example.com.com/ExamplePackage/ExamplePackage", from: "1.2.3"),
///         .package(url: "http://some/other/lib", .exact("1.2.3")),
///     ],
///     targets: [
///         .executableTarget(
///             name: "tool",
///             dependencies: [
///                 "Paper",
///                 "ExamplePackage"
///             ]),
///         .target(
///             name: "Paper",
///             dependencies: [
///                 "Basic",
///                 .target(name: "Utility"),
///                 .product(name: "AnotherExamplePackage"),
///             ])
///     ]
/// )
/// ```
public class Product {
    /// The name of the package product.
    public let name: String

    init(name: String) {
        self.name = name
    }

    /// The executable product of a Swift package.
    public final class Executable: Product, @unchecked Sendable {
        /// The names of the targets in this product.
        public let targets: [String]
        
        /// Any specific product settings that apply to this product.
        @_spi(PackageProductSettings)
        public let settings: [ProductSetting]

        init(name: String, targets: [String], settings: [ProductSetting]) {
            self.targets = targets
            self.settings = settings
            super.init(name: name)
        }
    }

    /// The library product of a Swift package.
    public final class Library: Product, @unchecked Sendable {
        /// The different types of a library product.
        public enum LibraryType: String {
            /// A statically linked library.
            case `static`
            /// A dynamically linked library.
            case `dynamic`
        }

        /// The names of the targets in this product.
        public let targets: [String]

        /// The type of the library.
        ///
        /// If the type is unspecified, the Swift Package Manager automatically chooses a type
        /// based on the client's preference.
        public let type: LibraryType?

        init(name: String, type: LibraryType? = nil, targets: [String]) {
            self.type = type
            self.targets = targets
            super.init(name: name)
        }
    }

    /// The plug-in product of a Swift package.
    public final class Plugin: Product, @unchecked Sendable {
        /// The name of the plug-in target to vend as a product.
        public let targets: [String]

        init(name: String, targets: [String]) {
            self.targets = targets
            super.init(name: name)
        }
    }

    /// Creates a library product to allow clients that declare a dependency on
    /// this package to use the package's functionality.
    ///
    /// A library's product can be either statically or dynamically linked. It's recommended
    /// that you don't explicitly declare the type of library, so Swift Package Manager can
    /// choose between static or dynamic linking based on the preference of the
    /// package's consumer.
    ///
    /// - Parameters:
    ///   - name: The name of the library product.
    ///   - type: The optional type of the library that's used to determine how to
    ///     link to the library. Leave this parameter so
    ///     Swift Package Manager can choose between static or dynamic linking (recommended). If you
    ///     don't support both linkage types, use
    ///     ``Product/Library/LibraryType/static`` or
    ///     ``Product/Library/LibraryType/dynamic`` for this parameter.
    ///   - targets: The targets that are bundled into a library product.
    ///
    /// - Returns: A `Product` instance.
    public static func library(
        name: String,
        type: Library.LibraryType? = nil,
        targets: [String]
    ) -> Product {
        return Library(name: name, type: type, targets: targets)
    }

    /// Creates an executable package product.
    ///
    /// - Parameters:
    ///   - name: The name of the executable product.
    ///   - targets: The targets to bundle into an executable product.
    /// - Returns: A `Product` instance.
    public static func executable(
        name: String,
        targets: [String]
    ) -> Product {
        return Executable(name: name, targets: targets, settings: [])
    }

    @_spi(PackageProductSettings)
    public static func executable(
        name: String,
        targets: [String],
        settings: [ProductSetting]
    ) -> Product {
        return Executable(name: name, targets: targets, settings: settings)
    }

    /// Defines a product that vends a package plugin target for use by clients of the package.
    ///
    /// It is not necessary to define a product for a plugin that
    /// is only used within the same package where you define it. All the targets
    /// listed must be plugin targets in the same package as the product. Swift Package Manager
    /// will apply them to any client targets of the product in the order
    /// they are listed.
    /// - Parameters:
    ///   - name: The name of the plugin product.
    ///   - targets: The plugin targets to vend as a product.
    /// - Returns: A `Product` instance.
    @available(_PackageDescription, introduced: 5.5)
    public static func plugin(
        name: String,
        targets: [String]
    ) -> Product {
        return Plugin(name: name, targets: targets)
    }
}


/// A particular setting to apply to a product. Some may be specific to certain platforms.
#if ENABLE_APPLE_PRODUCT_TYPES
public enum ProductSetting: Equatable {
    case bundleIdentifier(String)
    case teamIdentifier(String)
    case displayVersion(String)
    case bundleVersion(String)
    case iOSAppInfo(IOSAppInfo)

    public struct IOSAppInfo: Equatable {
        var appIcon: AppIcon?
        var accentColor: AccentColor?
        var supportedDeviceFamilies: [DeviceFamily]
        var supportedInterfaceOrientations: [InterfaceOrientation]
        var capabilities: [Capability] = []
        var appCategory: AppCategory?
        var additionalInfoPlistContentFilePath: String?

        // Represents the configuration of the app's accent color.
        public enum AccentColor: Equatable {
            public struct PresetColor: Equatable {
                public var rawValue: String

                public init(rawValue: String) {
                    self.rawValue = rawValue
                }
            }
            // Predefined color.
            case presetColor(PresetColor)
            // Named asset in an asset catalog.
            case asset(String)
        }

        // Represents the configuration of the app's app icon.
        public enum AppIcon: Equatable {
            public struct PlaceholderIcon: Equatable {
                public var rawValue: String

                public init(rawValue: String) {
                    self.rawValue = rawValue
                }
            }
            // Placeholder app icon using the app's accent color and specified icon.
            case placeholder(icon: PlaceholderIcon)
            // Named asset in an asset catalog.
            case asset(String)
        }
        
        /// Represents a family of device types that an application can support.
        public enum DeviceFamily: String, Equatable {
            case phone
            case pad
            case mac
        }
        
        /// Represents a condition on a particular device family.
        public struct DeviceFamilyCondition: Equatable {
            public var deviceFamilies: [DeviceFamily]
            
            public init(deviceFamilies: [DeviceFamily]) {
                self.deviceFamilies = deviceFamilies
            }
            public static func when(deviceFamilies: [DeviceFamily]) -> DeviceFamilyCondition {
                return DeviceFamilyCondition(deviceFamilies: deviceFamilies)
            }
        }
        
        /// Represents a supported device interface orientation.
        public enum InterfaceOrientation: Equatable {
            case portrait(_ condition: DeviceFamilyCondition? = nil)
            case portraitUpsideDown(_ condition: DeviceFamilyCondition? = nil)
            case landscapeRight(_ condition: DeviceFamilyCondition? = nil)
            case landscapeLeft(_ condition: DeviceFamilyCondition? = nil)

            public static var portrait: Self { portrait(nil) }
            public static var portraitUpsideDown: Self { portraitUpsideDown(nil) }
            public static var landscapeRight: Self { landscapeRight(nil) }
            public static var landscapeLeft: Self { landscapeLeft(nil) }
        }
        
        /// A capability required by the device.
        public enum Capability: Equatable {
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
        
        public struct AppTransportSecurityConfiguration: Equatable {
            public var allowsArbitraryLoadsInWebContent: Bool? = nil
            public var allowsArbitraryLoadsForMedia: Bool? = nil
            public var allowsLocalNetworking: Bool? = nil
            public var exceptionDomains: [ExceptionDomain]? = nil
            public var pinnedDomains: [PinnedDomain]? = nil

            public struct ExceptionDomain: Equatable {
                public var domainName: String
                public var includesSubdomains: Bool? = nil
                public var exceptionAllowsInsecureHTTPLoads: Bool? = nil
                public var exceptionMinimumTLSVersion: String? = nil
                public var exceptionRequiresForwardSecrecy: Bool? = nil
                public var requiresCertificateTransparency: Bool? = nil

                public init(
                    domainName: String,
                    includesSubdomains: Bool? = nil,
                    exceptionAllowsInsecureHTTPLoads: Bool? = nil,
                    exceptionMinimumTLSVersion: String? = nil,
                    exceptionRequiresForwardSecrecy: Bool? = nil,
                    requiresCertificateTransparency: Bool? = nil
                ) {
                    self.domainName = domainName
                    self.includesSubdomains = includesSubdomains
                    self.exceptionAllowsInsecureHTTPLoads = exceptionAllowsInsecureHTTPLoads
                    self.exceptionMinimumTLSVersion = exceptionMinimumTLSVersion
                    self.exceptionRequiresForwardSecrecy = exceptionRequiresForwardSecrecy
                    self.requiresCertificateTransparency = requiresCertificateTransparency
                }
            }
            
            public struct PinnedDomain: Equatable {
                public var domainName: String
                public var includesSubdomains : Bool? = nil
                public var pinnedCAIdentities : [[String: String]]? = nil
                public var pinnedLeafIdentities : [[String: String]]? = nil
                
                public init(
                    domainName: String,
                    includesSubdomains: Bool? = nil,
                    pinnedCAIdentities: [[String: String]]? = nil,
                    pinnedLeafIdentities: [[String: String]]? = nil
                ) {
                    self.domainName = domainName
                    self.includesSubdomains = includesSubdomains
                    self.pinnedCAIdentities = pinnedCAIdentities
                    self.pinnedLeafIdentities = pinnedLeafIdentities
                }
            }
            
            public init(
                allowsArbitraryLoadsInWebContent: Bool? = nil,
                allowsArbitraryLoadsForMedia: Bool? = nil,
                allowsLocalNetworking: Bool? = nil,
                exceptionDomains: [ExceptionDomain]? = nil,
                pinnedDomains: [PinnedDomain]? = nil
            ) {
                self.allowsArbitraryLoadsInWebContent = allowsArbitraryLoadsInWebContent
                self.allowsArbitraryLoadsForMedia = allowsArbitraryLoadsForMedia
                self.allowsLocalNetworking = allowsLocalNetworking
                self.exceptionDomains = exceptionDomains
                self.pinnedDomains = pinnedDomains
            }
        }

        public enum FileAccessLocation: Equatable {
            case userSelectedFiles
            case downloadsFolder
            case pictureFolder
            case musicFolder
            case moviesFolder

            var identifier: String {
                switch self {
                case .userSelectedFiles:
                    return "userSelectedFiles"
                case .downloadsFolder:
                    return "downloadsFolder"
                case .pictureFolder:
                    return "pictureFolder"
                case .musicFolder:
                    return "musicFolder"
                case .moviesFolder:
                    return "moviesFolder"
                }
            }
        }

        public enum FileAccessMode: Equatable {
            case readOnly
            case readWrite

            var identifier: String {
                switch self {
                case .readOnly: return "readOnly"
                case .readWrite: return "readWrite"
                }
            }
        }
        
        public struct AppCategory: Equatable, ExpressibleByStringLiteral {
            public var rawValue: String

            public init(rawValue: String) {
                self.rawValue = rawValue
            }

            public init(stringLiteral value: StringLiteralType) {
                self.init(rawValue: value)
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
#else
// This has to be defined at least as SPI because some of the methods that are
// SPI use it, but it doesn't contain anything when Apple product types aren't
// enabled.
@_spi(PackageProductSettings)
public enum ProductSetting: Equatable { }
#endif

#if ENABLE_APPLE_PRODUCT_TYPES
extension ProductSetting.IOSAppInfo.AccentColor.PresetColor {
    public static var blue: Self { .init(rawValue: "blue") }
    public static var brown: Self { .init(rawValue: "brown") }
    public static var cyan: Self { .init(rawValue: "cyan") }
    public static var green: Self { .init(rawValue: "green") }
    public static var indigo: Self { .init(rawValue: "indigo") }
    public static var mint: Self { .init(rawValue: "mint") }
    public static var orange: Self { .init(rawValue: "orange") }
    public static var pink: Self { .init(rawValue: "pink") }
    public static var purple: Self { .init(rawValue: "purple") }
    public static var red: Self { .init(rawValue: "red") }
    public static var teal: Self { .init(rawValue: "teal") }
    public static var yellow: Self { .init(rawValue: "yellow") }
}

extension ProductSetting.IOSAppInfo.AppIcon.PlaceholderIcon {
    public static var bandage: Self { .init(rawValue: "bandage")}
    public static var barChart: Self { .init(rawValue: "barChart")}
    public static var beachball: Self { .init(rawValue: "beachball")}
    public static var bicycle: Self { .init(rawValue: "bicycle")}
    public static var binoculars: Self { .init(rawValue: "binoculars")}
    public static var bird: Self { .init(rawValue: "bird") }
    public static var boat: Self { .init(rawValue: "boat")}
    public static var bowl: Self { .init(rawValue: "bowl")}
    public static var box: Self { .init(rawValue: "box")}
    public static var bunny: Self { .init(rawValue: "bunny")}
    public static var butterfly: Self { .init(rawValue: "butterfly")}
    public static var calculator: Self { .init(rawValue: "calculator")}
    public static var calendar: Self { .init(rawValue: "calendar")}
    public static var camera: Self { .init(rawValue: "camera")}
    public static var car: Self { .init(rawValue: "car")}
    public static var carrot: Self { .init(rawValue: "carrot")}
    public static var cat: Self { .init(rawValue: "cat")}
    public static var chatMessage: Self { .init(rawValue: "chatMessage")}
    public static var checkmark: Self { .init(rawValue: "checkmark")}
    public static var clock: Self { .init(rawValue: "clock")}
    public static var cloud: Self { .init(rawValue: "cloud")}
    public static var coffee: Self { .init(rawValue: "coffee")}
    public static var coins: Self { .init(rawValue: "coins")}
    public static var dog: Self { .init(rawValue: "dog")}
    public static var earth: Self { .init(rawValue: "earth")}
    public static var flower: Self { .init(rawValue: "flower")}
    public static var gamepad: Self { .init(rawValue: "gamepad")}
    public static var gift: Self { .init(rawValue: "gift")}
    public static var heart: Self { .init(rawValue: "heart")}
    public static var images: Self { .init(rawValue: "images")}
    public static var leaf: Self { .init(rawValue: "leaf")}
    public static var lightningBolt: Self { .init(rawValue: "lightningBolt")}
    public static var location: Self { .init(rawValue: "location")}
    public static var magicWand: Self { .init(rawValue: "magicWand")}
    public static var map: Self { .init(rawValue: "map")}
    public static var mic: Self { .init(rawValue: "mic")}
    public static var moon: Self { .init(rawValue: "moon")}
    public static var movieReel: Self { .init(rawValue: "movieReel")}
    public static var note: Self { .init(rawValue: "note")}
    public static var openBook: Self { .init(rawValue: "openBook")}
    public static var palette: Self { .init(rawValue: "palette")}
    public static var paper: Self { .init(rawValue: "paper")}
    public static var pencil: Self { .init(rawValue: "pencil")}
    public static var plane: Self { .init(rawValue: "plane")}
    public static var rocket: Self { .init(rawValue: "rocket")}
    public static var running: Self { .init(rawValue: "running")}
    public static var sandwich: Self { .init(rawValue: "sandwich")}
    public static var smiley: Self { .init(rawValue: "smiley")}
    public static var sparkle: Self { .init(rawValue: "sparkle")}
    public static var star: Self { .init(rawValue: "star")}
    public static var sun: Self { .init(rawValue: "sun")}
    public static var tv: Self { .init(rawValue: "tv")}
    public static var twoPeople: Self { .init(rawValue: "twoPeople")}
    public static var weights: Self { .init(rawValue: "weights")}
}

extension ProductSetting.IOSAppInfo.AppCategory {
    public static var books: Self { .init(rawValue: "public.app-category.books") }
    public static var business: Self { .init(rawValue: "public.app-category.business") }
    public static var developerTools: Self { .init(rawValue: "public.app-category.developer-tools") }
    public static var education: Self { .init(rawValue: "public.app-category.education") }
    public static var entertainment: Self { .init(rawValue: "public.app-category.entertainment") }
    public static var finance: Self { .init(rawValue: "public.app-category.finance") }
    public static var foodAndDrink: Self { .init(rawValue: "public.app-category.food-and-drink") }
    public static var graphicsDesign: Self { .init(rawValue: "public.app-category.graphics-design") }
    public static var healthcareFitness: Self { .init(rawValue: "public.app-category.healthcare-fitness") }
    public static var lifestyle: Self { .init(rawValue: "public.app-category.lifestyle") }
    public static var magazinesAndNewspapers: Self { .init(rawValue: "public.app-category.magazines-and-newspapers") }
    public static var medical: Self { .init(rawValue: "public.app-category.medical") }
    public static var music: Self { .init(rawValue: "public.app-category.music") }
    public static var navigation: Self { .init(rawValue: "public.app-category.navigation") }
    public static var news: Self { .init(rawValue: "public.app-category.news") }
    public static var photography: Self { .init(rawValue: "public.app-category.photography") }
    public static var productivity: Self { .init(rawValue: "public.app-category.productivity") }
    public static var reference: Self { .init(rawValue: "public.app-category.reference") }
    public static var shopping: Self { .init(rawValue: "public.app-category.shopping") }
    public static var socialNetworking: Self { .init(rawValue: "public.app-category.social-networking") }
    public static var sports: Self { .init(rawValue: "public.app-category.sports") }
    public static var travel: Self { .init(rawValue: "public.app-category.travel") }
    public static var utilities: Self { .init(rawValue: "public.app-category.utilities") }
    public static var video: Self { .init(rawValue: "public.app-category.video") }
    public static var weather: Self { .init(rawValue: "public.app-category.weather") }

    // Games
    public static var games: Self { .init(rawValue: "public.app-category.games") }
    // Games subcategories
    public static var actionGames: Self { .init(rawValue: "public.app-category.action-games") }
    public static var adventureGames: Self { .init(rawValue: "public.app-category.adventure-games") }
    public static var arcadeGames: Self { .init(rawValue: "public.app-category.arcade-games") }
    public static var boardGames: Self { .init(rawValue: "public.app-category.board-games") }
    public static var cardGames: Self { .init(rawValue: "public.app-category.card-games") }
    public static var casinoGames: Self { .init(rawValue: "public.app-category.casino-games") }
    public static var diceGames: Self { .init(rawValue: "public.app-category.dice-games") }
    public static var educationalGames: Self { .init(rawValue: "public.app-category.educational-games") }
    public static var familyGames: Self { .init(rawValue: "public.app-category.family-games") }
    public static var kidsGames: Self { .init(rawValue: "public.app-category.kids-games") }
    public static var musicGames: Self { .init(rawValue: "public.app-category.music-games") }
    public static var puzzleGames: Self { .init(rawValue: "public.app-category.puzzle-games") }
    public static var racingGames: Self { .init(rawValue: "public.app-category.racing-games") }
    public static var rolePlayingGames: Self { .init(rawValue: "public.app-category.role-playing-games") }
    public static var simulationGames: Self { .init(rawValue: "public.app-category.simulation-games") }
    public static var sportsGames: Self { .init(rawValue: "public.app-category.sports-games") }
    public static var strategyGames: Self { .init(rawValue: "public.app-category.strategy-games") }
    public static var triviaGames: Self { .init(rawValue: "public.app-category.trivia-games") }
    public static var wordGames: Self { .init(rawValue: "public.app-category.word-games") }
}
#endif
