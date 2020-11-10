/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import SourceControl

struct MultipleErrors: Error {
    let errors: [Error]

    init(_ errors: [Error]) {
        self.errors = errors
    }
}

struct NotFoundError: Error {
    let item: String

    init(_ item: String) {
        self.item = item
    }
}

internal extension Result {
    var failure: Failure? {
        switch self {
        case .failure(let failure):
            return failure
        case .success:
            return nil
        }
    }

    var success: Success? {
        switch self {
        case .failure:
            return nil
        case .success(let value):
            return value
        }
    }
}

// Model Extension

extension PackageReference {
    /// Initializes a `PackageReference` from `RepositorySpecifier`
    init(repository: RepositorySpecifier, kind: PackageReference.Kind = .remote) {
        self.init(
            identity: PackageReference.computeIdentity(packageURL: repository.url),
            path: repository.url,
            kind: kind
        )
    }
}
