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

/// Builder for resolved product.
final class MemoizedResolvedProduct: Memoized<ResolvedProduct> {
    /// The reference to its package.
    unowned let memoizedPackage: MemoizedResolvedPackage

    /// The product reference.
    let product: Product

    /// The target builders in the product.
    let targets: [MemoizedResolvedTarget]

    init(product: Product, memoizedPackage: MemoizedResolvedPackage, targets: [MemoizedResolvedTarget]) {
        self.product = product
        self.memoizedPackage = memoizedPackage
        self.targets = targets
    }

    override func constructImpl() throws -> ResolvedProduct {
        try ResolvedProduct(
            product: self.product,
            targets: self.targets.map { try $0.construct() }
        )
    }
}
