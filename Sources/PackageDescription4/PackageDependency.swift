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
        // FIXME: This is suboptimal but its the only way to do this right now.
      #if PACKAGE_DESCRIPTION_4
        precondition(requirement != .localPackageItem, "Use `.package(path:)` API to declare a local package dependency")
      #elseif PACKAGE_DESCRIPTION_4_2
        precondition(requirement != ._localPackageItem, "Use `.package(path:)` API to declare a local package dependency")
      #endif
        return .init(url: url, requirement: requirement)
    }

    // Add a dependency given a range requirement.
    public static func package(
        url: String,
        _ range: Range<Version>
    ) -> Package.Dependency {
      #if PACKAGE_DESCRIPTION_4_2
        return .init(url: url, requirement: ._rangeItem(range))
      #else
        return .init(url: url, requirement: .rangeItem(range))
      #endif
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

  #if PACKAGE_DESCRIPTION_4_2
    /// Add a dependency to a local package on the filesystem.
    public static func package(
        path: String
    ) -> Package.Dependency {
        return .init(url: path, requirement: ._localPackageItem)
    }
  #endif

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

// Mark common APIs used by mistake as unavailable to provide better error messages.
extension Package.Dependency {
    @available(*, unavailable, message: "use package(url:_:) with the .exact(Version) initializer instead")
    public static func package(url: String, version: Version) -> Package.Dependency {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:_:) with the .branch(String) initializer instead")
    public static func package(url: String, branch: String) -> Package.Dependency {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:_:) with the .revision(String) initializer instead")
    public static func package(url: String, revision: String) -> Package.Dependency {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:_:) without the range label instead")
    public static func package(url: String, range: Range<Version>) -> Package.Dependency {
        fatalError()
    }
}
