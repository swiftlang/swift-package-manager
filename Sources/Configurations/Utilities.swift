/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import Foundation

extension FileSystem {
    func readFileContents(_ path: AbsolutePath) throws -> Data {
        return try Data(self.readFileContents(path).contents)
    }

    func writeFileContents(_ path: AbsolutePath, data: Data) throws {
        return try self.writeFileContents(path, bytes: ByteString(data))
    }
}
