/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(PackageProductSettings) import PackageDescription

#if ENABLE_APPLE_PRODUCT_TYPES
extension Product {
    /// Creates an iOS application package product.
    ///
    /// - Parameters:
    ///     - name: The name of the application product.
    ///     - targets: The targets to include in the application product; one and only one of them should be an executable target.
    ///     - settings: The settings that define the core properties of the application.
    public static func iOSApplication(
        name: String,
        targets: [String],
        bundleIdentifier: String? = nil,
        teamIdentifier: String? = nil,
        displayVersion: String? = nil,
        bundleVersion: String? = nil,
        iconAssetName: String? = nil,
        accentColorAssetName: String? = nil,
        supportedDeviceFamilies: [ProductSetting.IOSAppInfo.DeviceFamily],
        supportedInterfaceOrientations: [ProductSetting.IOSAppInfo.InterfaceOrientation],
        capabilities: [ProductSetting.IOSAppInfo.Capability] = [],
        additionalInfoPlistContentFilePath: String? = nil
    ) -> Product {
        return iOSApplication(
            name: name,
            targets: targets,
            bundleIdentifier: bundleIdentifier,
            teamIdentifier: teamIdentifier,
            displayVersion: displayVersion,
            bundleVersion: bundleVersion,
            appIcon: iconAssetName.map({ .asset($0) }),
            accentColor: accentColorAssetName.map({ .asset($0) }),
            supportedDeviceFamilies: supportedDeviceFamilies,
            supportedInterfaceOrientations: supportedInterfaceOrientations,
            capabilities: capabilities,
            additionalInfoPlistContentFilePath: additionalInfoPlistContentFilePath
        )
    }

    /// Creates an iOS application package product.
    ///
    /// - Parameters:
    ///     - name: The name of the application product.
    ///     - targets: The targets to include in the application product; one and only one of them should be an executable target.
    ///     - settings: The settings that define the core properties of the application.
    @available(_PackageDescription, introduced: 5.6)
    public static func iOSApplication(
        name: String,
        targets: [String],
        bundleIdentifier: String? = nil,
        teamIdentifier: String? = nil,
        displayVersion: String? = nil,
        bundleVersion: String? = nil,
        appIcon: ProductSetting.IOSAppInfo.AppIcon? = nil,
        accentColor: ProductSetting.IOSAppInfo.AccentColor? = nil,
        supportedDeviceFamilies: [ProductSetting.IOSAppInfo.DeviceFamily],
        supportedInterfaceOrientations: [ProductSetting.IOSAppInfo.InterfaceOrientation],
        capabilities: [ProductSetting.IOSAppInfo.Capability] = [],
        appCategory: ProductSetting.IOSAppInfo.AppCategory? = nil,
        additionalInfoPlistContentFilePath: String? = nil
    ) -> Product {
        return .executable(name: name, targets: targets, settings: [
            bundleIdentifier.map{ .bundleIdentifier($0) },
            teamIdentifier.map{ .teamIdentifier($0) },
            displayVersion.map{ .displayVersion($0) },
            bundleVersion.map{ .bundleVersion($0) },
            .iOSAppInfo(ProductSetting.IOSAppInfo(
                appIcon: appIcon,
                accentColor: accentColor,
                supportedDeviceFamilies: supportedDeviceFamilies,
                supportedInterfaceOrientations: supportedInterfaceOrientations,
                capabilities: capabilities,
                appCategory: appCategory,
                additionalInfoPlistContentFilePath: additionalInfoPlistContentFilePath
            ))
        ].compactMap{ $0 })
    }
}
#endif
