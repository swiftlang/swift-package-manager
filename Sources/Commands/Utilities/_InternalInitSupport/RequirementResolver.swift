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

import PackageModel
import TSCBasic
import TSCUtility

struct DependencyRequirementResolver {
    let exact: Version?
    let revision: String?
    let branch: String?
    let from: Version?
    let upToNextMinorFrom: Version?
    let to: Version?

    func resolve() throws -> PackageDependency.SourceControl.Requirement {
        var all: [PackageDependency.SourceControl.Requirement] = []

        if let v = exact { all.append(.exact(v)) }
        if let b = branch { all.append(.branch(b)) }
        if let r = revision { all.append(.revision(r)) }
        if let f = from { all.append(.range(.upToNextMajor(from: f))) }
        if let u = upToNextMinorFrom { all.append(.range(.upToNextMinor(from: u))) }

        guard all.count == 1, let requirement = all.first else {
            throw StringError("Specify exactly one version requirement.")
        }

        if case .range(let range) = requirement, let upper = to {
            return .range(range.lowerBound ..< upper)
        } else if to != nil {
            throw StringError("--to requires --from or --up-to-next-minor-from")
        }

        return requirement
    }
}
