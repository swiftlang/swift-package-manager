//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.URL

extension URL {
    /// Returns the path of the file URL.
    ///
    /// This should always be used whenever the file path equivalent of a URL is needed. DO NOT use ``path`` or ``path(percentEncoded:)``, as these deal in terms of the path portion of the URL representation per RFC8089, which on Windows would include a leading slash.
    ///
    /// - throws: ``FileURLError`` if the URL does not represent a file or its path is otherwise not representable.
    public var filePath: AbsolutePath {
        get throws {
            guard isFileURL else {
                throw FileURLError.notRepresentable(self)
            }
            return try withUnsafeFileSystemRepresentation { cString in
                guard let cString else {
                    throw FileURLError.notRepresentable(self)
                }
                return try AbsolutePath(validating: String(cString: cString))
            }
        }
    }
}

fileprivate enum FileURLError: Error {
    case notRepresentable(URL)
}
