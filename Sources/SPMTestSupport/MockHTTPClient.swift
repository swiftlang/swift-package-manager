/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import TSCBasic
import TSCUtility

extension HTTPClient {
    public static func mock(fileSystem: FileSystem) -> HTTPClient {
        let handler: HTTPClient.Handler = { request, _, completion in
            switch request.kind {
            case.generic:
                completion(.success(.okay(body: request.url.absoluteString)))
            case .download(let fileSystem, let destination):
                do {
                    try fileSystem.writeFileContents(
                        destination,
                        bytes: ByteString(encodingAsUTF8: request.url.absoluteString),
                        atomically: true
                    )
                    completion(.success(.okay(body: request.url.absoluteString)))
                } catch {
                    completion(.failure(error))
                }
            }
        }
        return HTTPClient(handler: handler)
    }
}
