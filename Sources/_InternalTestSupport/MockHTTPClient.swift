//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

extension HTTPClient {
    public static func mock(fileSystem: FileSystem) -> HTTPClient {
        HTTPClient { request, _ in
            switch request.kind {
            case.generic:
                return .okay(body: request.url.absoluteString)

            case .download(let fileSystem, let destination):
                try fileSystem.writeFileContents(
                    destination,
                    string: request.url.absoluteString
                )
                return .okay(body: request.url.absoluteString)
            }
        }
    }
}
