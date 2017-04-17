/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility
import PackageDescription4

extension Utility.Version {
    /// Create Utility.Version object from PackageDescription4.Version object.
    public init(pdVersion version: PackageDescription4.Version) {
        self.init(
            version.major, version.minor, version.patch,
            prereleaseIdentifiers: version.prereleaseIdentifiers,
            buildMetadataIdentifiers: version.buildMetadataIdentifiers)
    }

    /// Returns PackageDescription4.Version representation.
    public var asPD4Version: PackageDescription4.Version {
        return PackageDescription4.Version(
            major, minor, patch,
            prereleaseIdentifiers: prereleaseIdentifiers,
            buildMetadataIdentifiers: buildMetadataIdentifiers)
    }
}

extension Range where Bound == PackageDescription4.Version {
    /// Converts PackageDescription.Version Range to Utility.Version Range.
    public var asUtilityVersion: Range<Utility.Version> {
        return Utility.Version(pdVersion: lowerBound) ..< Utility.Version(pdVersion: upperBound)
    }
}
