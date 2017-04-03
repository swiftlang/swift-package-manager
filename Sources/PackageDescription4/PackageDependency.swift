/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension Package.Dependency: Equatable {

    // Add a dependency starting from a minimum version, going upto the next
    // major version.
    public static func package(
        url: String,
        from version: Version
    ) -> Package.Dependency {
        return .package(url: url, .upToNextMajor(from: version))
    }

    // Add a dependency given a requirement.
    public static func package(
        url: String,
        _ requirement: Package.Dependency.Requirement
    ) -> Package.Dependency {
        return .init(url: url, requirement: requirement)
    }

    // Add a dependency given a range requirement.
    public static func package(
        url: String,
        _ range: Range<Version>
    ) -> Package.Dependency {
        return .init(url: url, requirement: .rangeItem(range))
    }

    // Add a dependency given a closed range requirement.
    public static func package(
        url: String,
        _ range: ClosedRange<Version>
    ) -> Package.Dependency {
        // Increase upperbound's patch version by one.
        let upper = range.upperBound
        let upperBound = Version(
            upper.major, upper.minor, upper.patch + 1,
            prereleaseIdentifiers: upper.prereleaseIdentifiers,
            buildMetadataIdentifiers: upper.buildMetadataIdentifiers)
        return .package(url: url, range.lowerBound..<upperBound)
    }

    public static func == (lhs: Package.Dependency, rhs: Package.Dependency) -> Bool {
        return lhs.url == rhs.url && lhs.requirement == rhs.requirement
    }

    func toJSON() -> JSON {
        return .dictionary([
            "url": .string(url),
            "requirement": requirement.toJSON(),
        ])
    }
}
