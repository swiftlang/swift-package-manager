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

import Basics
import Foundation
import PackageCollections
import PackageGraph
import PackageModel
import SourceControl
import TSCUtility

internal struct SBOMGitInfo {
    internal let version: SBOMComponent.Version
    internal let originator: SBOMOriginator

    internal init(version: SBOMComponent.Version, originator: SBOMOriginator) {
        self.version = version
        self.originator = originator
    }
}

/// Cache for storing root package Git info (to minimize calls to Git)
internal actor SBOMGitCache {
    private var cache: [PackageIdentity: SBOMGitInfo] = [:]
    internal func get(_ identity: PackageIdentity) -> SBOMGitInfo? {
        self.cache[identity]
    }

    internal func set(_ identity: PackageIdentity, gitInfo: SBOMGitInfo) {
        self.cache[identity] = gitInfo
    }
}

/// Cache for storing extracted components (to avoid redundant extraction)
internal actor SBOMComponentCache {
    private var packageCache: [PackageIdentity: SBOMComponent] = [:]
    private var productCache: [String: SBOMComponent] = [:] // key: "packageIdentity:productName"

    internal func getPackage(_ identity: PackageIdentity) -> SBOMComponent? {
        self.packageCache[identity]
    }

    internal func setPackage(_ identity: PackageIdentity, component: SBOMComponent) {
        self.packageCache[identity] = component
    }

    internal func getProduct(_ packageIdentity: PackageIdentity, productName: String) -> SBOMComponent? {
        let key = "\(packageIdentity):\(productName)"
        return self.productCache[key]
    }

    internal func setProduct(_ packageIdentity: PackageIdentity, productName: String, component: SBOMComponent) {
        let key = "\(packageIdentity):\(productName)"
        self.productCache[key] = component
    }
}

/// Cache for storing module-to-target-name mappings from the build graph
internal actor SBOMTargetNameCache {
    private var cache: [ResolvedModule.ID: String] = [:]

    internal func get(_ moduleID: ResolvedModule.ID) -> String? {
        self.cache[moduleID]
    }

    internal func set(_ moduleID: ResolvedModule.ID, targetName: String) {
        self.cache[moduleID] = targetName
    }
}

/// Consolidated container for all SBOM extraction caches
internal struct SBOMCaches {
    internal let git: SBOMGitCache
    internal let component: SBOMComponentCache
    internal let targetName: SBOMTargetNameCache

    internal init() {
        self.git = SBOMGitCache()
        self.component = SBOMComponentCache()
        self.targetName = SBOMTargetNameCache()
    }

    internal init(
        git: SBOMGitCache,
        component: SBOMComponentCache,
        targetName: SBOMTargetNameCache
    ) {
        self.git = git
        self.component = component
        self.targetName = targetName
    }
}
