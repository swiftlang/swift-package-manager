/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

//===----------------------------------------------------------------------===//
//
// This source file is part of the Vapor open source project
//
// Copyright (c) 2017-2020 Vapor project authors
// Licensed under MIT
//
// See LICENSE for license information
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

import Foundation

// Reference: https://github.com/vapor/jwt-kit/blob/master/Sources/JWTKit/Utilities/Utilities.swift

extension DataProtocol {
    func copyBytes() -> [UInt8] {
        [UInt8](unsafeUninitializedCapacity: self.count) { buffer, initializedCount in
            self.copyBytes(to: buffer)
            initializedCount = self.count
        }
    }
}
