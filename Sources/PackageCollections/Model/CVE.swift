//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.URL

extension PackageCollectionsModel {
    /// A representation of Common Vulnerabilities and Exposures (CVE)
    public struct CVE: Equatable {
        /// CVE identifier
        public let identifier: String

        /// URL of the CVE
        public let url: URL
    }
}
