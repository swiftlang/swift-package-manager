//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2019-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct TSCUtility.Version

extension Version {
    func nextPatch() -> Version {
        if self.prereleaseIdentifiers.isEmpty {
            return Version(self.major, self.minor, self.patch + 1)
        } else {
            return Version(self.major, self.minor, self.patch, prereleaseIdentifiers: self.prereleaseIdentifiers + ["0"])
        }
    }
}
