/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility
import Foundation

public class MockArchiver: Archiver {
    public typealias Extract = (
        AbsolutePath,
        AbsolutePath,
        (Result<Void, Error>) -> Void
    ) -> Void

    public struct Extraction: Equatable {
        public let archivePath: AbsolutePath
        public let destinationPath: AbsolutePath
    }

    public let supportedExtensions: Set<String> = ["zip"]
    public var extractions: [Extraction] = []
    public var extract: Extract!

    public init(extract: Extract? = nil) {
        self.extract = extract ?? { archivePath, destinationPath, completion in
            self.extractions.append(Extraction(archivePath: archivePath, destinationPath: destinationPath))
            completion(.success(()))
        }
    }

    public func extract(
        from archivePath: AbsolutePath,
        to destinationPath: AbsolutePath,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.extract(archivePath, destinationPath, completion)
    }
}
