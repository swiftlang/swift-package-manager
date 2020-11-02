/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageModel
import SourceControl

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
