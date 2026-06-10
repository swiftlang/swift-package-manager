//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Protocol defining filtering behavior for SBOM components and relationships
protocol SBOMFilterStrategy {
    /// Determines whether a component should be included based on the filter criteria
    func shouldIncludeComponent(_ component: SBOMComponent, primaryComponent: SBOMComponent) -> Bool
    
    /// Determines whether a relationship should be tracked based on the filter criteria
    func shouldTrackRelationship(
        parent: SBOMComponent,
        child: SBOMComponent,
        primaryComponent: SBOMComponent
    ) -> Bool
}

/// Filter strategy that includes all components and relationships
struct AllFilterStrategy: SBOMFilterStrategy {
    func shouldIncludeComponent(_ component: SBOMComponent, primaryComponent: SBOMComponent) -> Bool {
        return true // All filter includes everything
    }
    
    func shouldTrackRelationship(
        parent: SBOMComponent,
        child: SBOMComponent,
        primaryComponent: SBOMComponent
    ) -> Bool {
        return parent != child // prevent self-referential dependencies
    }
}

/// Filter strategy that only includes product-level components and relationships
struct ProductFilterStrategy: SBOMFilterStrategy {
    func shouldIncludeComponent(_ component: SBOMComponent, primaryComponent: SBOMComponent) -> Bool {
        // Always include products
        if component.entity == .product {
            return true
        }
        // If the primary component is a package, also include that root package so that the primary component can connect to the products
        if primaryComponent.entity == .package && component.id == primaryComponent.id {
            return true
        }
        return false
    }
    
    func shouldTrackRelationship(
        parent: SBOMComponent,
        child: SBOMComponent,
        primaryComponent: SBOMComponent
    ) -> Bool {
        // prevent self-referential dependencies
        guard parent != child else { return false } 
        if child.entity == .product {
            // if the primary component is a product, then include product-product relationships
            if parent.entity == .product {
                return true
            }
            // if the primary component is a package, then need to also include root-package-to-root-product relationship(s) for a full graph
            if primaryComponent.entity == .package && parent.id == primaryComponent.id {
                return true
            }
        }
        return false
    }
}

/// Filter strategy that only includes package-level components and relationships
struct PackageFilterStrategy: SBOMFilterStrategy {
    func shouldIncludeComponent(_ component: SBOMComponent, primaryComponent: SBOMComponent) -> Bool {
        // Always include packages
        if component.entity == .package {
            return true
        }
        // If the primary component is a product, also include that product
        // This allows package-to-product relationships when the root is a product
        if primaryComponent.entity == .product && component.id == primaryComponent.id {
            return true
        }
        return false
    }
    
    func shouldTrackRelationship(
        parent: SBOMComponent,
        child: SBOMComponent,
        primaryComponent: SBOMComponent
    ) -> Bool {
        // prevent self-referential dependencies
        guard parent != child else { return false } 
        if parent.entity == .package {
            // always include package-to-package relationships
            if child.entity == .package {
                return true
            }
            // If the primary component is a product, then include package-to-product relationship for a full graph
            if primaryComponent.entity == .product && child.id == primaryComponent.id {
                return true
            }
        }
        return false
    }
}

extension Filter {
    /// Creates the appropriate filter strategy for this filter type
    func createStrategy() -> SBOMFilterStrategy {
        switch self {
        case .all:
            return AllFilterStrategy()
        case .product:
            return ProductFilterStrategy()
        case .package:
            return PackageFilterStrategy()
        }
    }
}
