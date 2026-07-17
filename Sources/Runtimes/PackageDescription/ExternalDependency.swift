//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A product exported by an external package
public final class ExternalProduct {
    /// The product exported
    public var product: Product

    /// The target for the product with build settings that dependants of this product
    /// need to set on themselves.
    public var target: Target

    init(product: Product, target: Target) {
        self.product = product
        self.target = target
    }
}

extension ExternalProduct {
    public static func library(
        name: String,
        type: Product.Library.LibraryType,
        cSettings: [CSetting]? = nil,
        cxxSettings: [CXXSetting]? = nil,
        swiftSettings: [SwiftSetting]? = nil,
        linkerSettings: [LinkerSetting]? = nil
    ) -> ExternalProduct {
        .init(
            product: Product.Library(
                name: name,
                type: type,
                targets: [name]
            ),
            target: Target(
                name: name,
                dependencies: [],
                path: nil,
                exclude: [],
                sources: nil,
                publicHeadersPath: nil,
                type: .external,
                packageAccess: false,
                cSettings: cSettings,
                cxxSettings: cxxSettings,
                swiftSettings: swiftSettings,
                linkerSettings: linkerSettings
            )
        )
    }
}
