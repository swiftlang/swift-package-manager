//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class PackageModel.Product

/// Caching container for resolved products.
final class CachedResolvedProduct: Cacheable<ResolvedProduct> {
    /// The reference to its package.
    unowned let cachedPackage: CachedResolvedPackage

    /// The product reference.
    let product: Product

    /// Cached resolved targets in the product.
    let targets: [CachedResolvedTarget]

    init(product: Product, cachedPackage: CachedResolvedPackage, targets: [CachedResolvedTarget]) {
        self.product = product
        self.cachedPackage = cachedPackage
        self.targets = targets
    }

    override func constructImpl() throws -> ResolvedProduct {
        try ResolvedProduct(
            product: self.product,
            targets: self.targets.map { try $0.construct() }
        )
    }
}
