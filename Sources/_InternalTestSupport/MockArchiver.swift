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

package final class MockArchiver: Archiver {
    package typealias ExtractionHandler = @Sendable (
        MockArchiver,
        AbsolutePath,
        AbsolutePath,
        (Result<Void, Error>) -> Void
    ) throws -> Void
    package typealias CompressionHandler = @Sendable (
        MockArchiver,
        AbsolutePath,
        AbsolutePath
    ) async throws -> Void
    package typealias ValidationHandler = @Sendable (
        MockArchiver,
        AbsolutePath,
        (Result<Bool, Error>) -> Void
    ) throws -> Void

    package struct Extraction: Equatable {
        public let archivePath: AbsolutePath
        public let destinationPath: AbsolutePath

        public init(archivePath: AbsolutePath, destinationPath: AbsolutePath) {
            self.archivePath = archivePath
            self.destinationPath = destinationPath
        }
    }

    package struct Compression: Equatable {
        public let paths: [RelativePath]
        public let parent: AbsolutePath
        public let destinationPath: AbsolutePath

        public init(paths: [RelativePath], parent: AbsolutePath, destinationPath: AbsolutePath) {
            self.paths = paths
            self.parent = parent
            self.destinationPath = destinationPath
        }
    }

    package let supportedExtensions: Set<String> = ["zip"]
    package let extractions = ThreadSafeArrayStore<Extraction>()
    package let compressions = ThreadSafeArrayStore<Compression>()
    package let extractionHandler: ExtractionHandler?
    package let compressionHandler: CompressionHandler?
    package let validationHandler: ValidationHandler?

    package convenience init(handler: ExtractionHandler? = .none) {
        self.init(extractionHandler: handler, compressionHandler: .none, validationHandler: .none)
    }

    package init(
        extractionHandler: ExtractionHandler? = .none,
        compressionHandler: CompressionHandler? = .none,
        validationHandler: ValidationHandler? = .none
    ) {
        self.extractionHandler = extractionHandler
        self.compressionHandler = compressionHandler
        self.validationHandler = validationHandler
    }

    package func extract(
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

    package func compress(
        directory: AbsolutePath,
        to destinationPath: AbsolutePath
    ) async throws {
        guard let handler = self.compressionHandler else {
            try self.compressions.append(Compression(
                paths: [RelativePath(validating: directory.basename)],
                parent: directory.parentDirectory,
                destinationPath: destinationPath
            ))
            return
        }
        try await handler(self, directory, destinationPath)
    }

    package func compress(paths: [RelativePath], from parent: AbsolutePath, to destinationPath: AbsolutePath) async throws {
        self.compressions.append(Compression(paths: paths, parent: parent, destinationPath: destinationPath))
    }

    package func validate(path: AbsolutePath, completion: @escaping (Result<Bool, Error>) -> Void) {
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
