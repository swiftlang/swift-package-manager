/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// The supported manifest versions.
///
/// ManifestVersion should never be public type.
enum ManifestVersion: String, Codable, CaseIterable {
    case v4
    case v4_2
    case v5

    // We will need to audit all VersionedValue instances when adding a new
    // manifest version. Maybe versioned value should take a range of supported
    // manifest versions?
}

/// A value that is available in a set of manifest version.
///
/// This is for mimicking something like the availability attribute for
/// PackageDescription APIs.
/// VersionedValue should never be public type.
struct VersionedValue<T: Encodable>: Encodable {
    let supportedVersions: [ManifestVersion]
    let value: T
    let api: String

    init(_ value: T, api: String, versions: [ManifestVersion] = ManifestVersion.allCases) {
        self.api = api
        self.supportedVersions = versions
        self.value = value
    }
}
