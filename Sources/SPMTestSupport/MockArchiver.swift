/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import TSCBasic
import TSCUtility

public class MockArchiver: Archiver {
    public typealias Handler = (MockArchiver, AbsolutePath, AbsolutePath, (Result<Void, Error>) -> Void) -> Void

    public struct Extraction: Equatable {
        public let archivePath: AbsolutePath
        public let destinationPath: AbsolutePath

        public init(archivePath: AbsolutePath, destinationPath: AbsolutePath) {
            self.archivePath = archivePath
            self.destinationPath = destinationPath
        }
    }

    public let supportedExtensions: Set<String> = ["zip"]
    public let extractions = ThreadSafeArrayStore<Extraction>()
    public let handler: Handler?

    public init(handler: Handler? = nil) {
        self.handler = handler
    }

    public func extract(
        from archivePath: AbsolutePath,
        to destinationPath: AbsolutePath,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if let handler = self.handler {
            handler(self, archivePath, destinationPath, completion)
        } else {
            self.extractions.append(Extraction(archivePath: archivePath, destinationPath: destinationPath))
            completion(.success(()))
        }
    }
}
