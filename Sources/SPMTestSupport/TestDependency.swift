/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import TSCBasic

public struct TestDependency {
    public typealias Requirement = PackageDependencyDescription.Requirement

    public let name: String?
    public let path: String
    public let requirement: Requirement

    public init(name: String, requirement: Requirement) {
        self.name = name
        self.path = name
        self.requirement = requirement
    }

    public init(name: String?, path: String, requirement: Requirement) {
        self.name = name
        self.path = path
        self.requirement = requirement
    }

    public func convert(baseURL: AbsolutePath) -> PackageDependencyDescription {
        return PackageDependencyDescription(
            name: self.name,
            url: baseURL.appending(RelativePath(self.path)).pathString,
            requirement: self.requirement
        )
    }
}
