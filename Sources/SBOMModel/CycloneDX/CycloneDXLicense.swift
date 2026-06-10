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

internal struct CycloneDXLicenseInfo: Codable, Equatable {
    internal let id: String
    internal let url: String?

    internal init(
        id: String,
        url: String?
    ) {
        self.id = id
        self.url = url
    }
}

internal struct CycloneDXLicense: Codable, Equatable {
    internal let license: CycloneDXLicenseInfo

    internal init(
        license: CycloneDXLicenseInfo,
    ) {
        self.license = license
    }
}
