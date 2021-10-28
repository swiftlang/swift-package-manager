/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import PackageModel
import TSCBasic

public extension PackageDependency {
    static func fileSystem(
        identity: PackageIdentity? = nil,
        deprecatedName: String? = nil,
        path: AbsolutePath
    ) -> Self {
        let identity = identity ?? PackageIdentity(path: path)
        return .fileSystem(
            identity: identity,
            nameForTargetDependencyResolutionOnly: deprecatedName,
            path: path
        )
    }
    
    static func localSourceControl(
        identity: PackageIdentity? = nil,
        deprecatedName: String? = nil,
        path: AbsolutePath,
        requirement: SourceControl.Requirement
    ) -> Self {
        let identity = identity ?? PackageIdentity(path: path)
        return .localSourceControl(
            identity: identity,
            nameForTargetDependencyResolutionOnly: deprecatedName,
            path: path,
            requirement: requirement
        )
    }
    
    static func remoteSourceControl(
        identity: PackageIdentity? = nil,
        deprecatedName: String? = nil,
        url: Foundation.URL,
        requirement: SourceControl.Requirement
    ) -> Self {
        let identity = identity ?? PackageIdentity(url: url)
        return .remoteSourceControl(
            identity: identity,
            nameForTargetDependencyResolutionOnly: deprecatedName,
            url: url,
            requirement: requirement
        )
    }
    
    static func registry(identity: String, requirement: Registry.Requirement) -> Self {
        return .registry(
            identity: .plain(identity),
            requirement: requirement
        )
    }
}

// backwards compatibility with existing tests
extension PackageDependency.SourceControl.Requirement {
    public static func upToNextMajor(from version: Version) -> Self {
        return .range(.upToNextMajor(from: version))
    }
    public static func upToNextMinor(from version: Version) -> Self {
        return .range(.upToNextMinor(from: version))
    }
}
