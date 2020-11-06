/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic

extension PackageCollections {
    public struct Storage: Closable {
        let collectionsProfiles: PackageCollectionsProfileStorage
        let collections: PackageCollectionsStorage

        public init(collectionsProfiles: PackageCollectionsProfileStorage, collections: PackageCollectionsStorage) {
            self.collectionsProfiles = collectionsProfiles
            self.collections = collections
        }
    }
}

extension PackageCollections.Storage {
    public func close() throws {
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

        tryClose(self.collectionsProfiles)
        tryClose(self.collections)

        if !errors.isEmpty {
            throw MultipleErrors(errors)
        }
    }
}
