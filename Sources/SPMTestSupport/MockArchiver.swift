//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import TSCBasic

public class MockArchiver: Archiver {
    public typealias ExtractionHandler = (MockArchiver, AbsolutePath, AbsolutePath, (Result<Void, Error>) -> Void) throws -> Void
    public typealias ValidationHandler = (MockArchiver, AbsolutePath, (Result<Bool, Error>) -> Void) throws -> Void

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
    public let extractionHandler: ExtractionHandler?
    public let validationHandler: ValidationHandler?

    public convenience init(handler: ExtractionHandler? = nil) {
        self.init(extractionHandler: handler, validationHandler: nil)
    }

    public init(extractionHandler: ExtractionHandler? = nil, validationHandler: ValidationHandler? = nil) {
        self.extractionHandler = extractionHandler
        self.validationHandler = validationHandler
    }

    public func extract(
        from archivePath: AbsolutePath,
        to destinationPath: AbsolutePath,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            if let handler = self.extractionHandler {
                try handler(self, archivePath, destinationPath, completion)
            } else {
                self.extractions.append(Extraction(archivePath: archivePath, destinationPath: destinationPath))
                completion(.success(()))
            }
        } catch {
            completion(.failure(error))
        }
    }

    public func validate(path: AbsolutePath, completion: @escaping (Result<Bool, Error>) -> Void) {
        do {
            if let handler = self.validationHandler {
                try handler(self, path, completion)
            } else {
                completion(.success(true))
            }
        } catch {
            completion(.failure(error))
        }
    }
}
