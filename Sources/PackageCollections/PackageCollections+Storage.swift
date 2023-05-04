//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import protocol TSCBasic.Closable

extension PackageCollections {
    struct Storage: Closable {
        let sources: PackageCollectionsSourcesStorage
        let collections: PackageCollectionsStorage

        init(sources: PackageCollectionsSourcesStorage, collections: PackageCollectionsStorage) {
            self.sources = sources
            self.collections = collections
        }
    }
}

extension PackageCollections.Storage {
    func close() throws {
        var errors = [Error]()

        let tryClose = { (item: Any) in
            if let closable = item as? Closable {
                do {
                    try closable.close()
                } catch {
                    errors.append(error)
                }
            }
        }

        tryClose(self.sources)
        tryClose(self.collections)

        if !errors.isEmpty {
            throw MultipleErrors(errors)
        }
    }
}
