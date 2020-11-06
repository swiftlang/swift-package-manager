/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.Date
import struct Foundation.URL
@testable import PackageCollections
import SourceControl
import TSCUtility

func makeMockSources(count: Int = Int.random(in: 5 ... 10)) -> [PackageCollectionsModel.PackageCollectionSource] {
    return (0 ..< count).map { index in
        .feed(URL(string: "https://source-\(index)")!)
    }
}

func makeMockCollections(count: Int = Int.random(in: 50 ... 100)) -> [PackageCollectionsModel.PackageCollection] {
    return (0 ..< count).map { collectionIndex in
        let packages = (0 ..< Int.random(in: 1 ... 15)).map { packageIndex -> PackageCollectionsModel.PackageCollection.Package in
            let versions = (0 ..< Int.random(in: 1 ... 10)).map { versionIndex -> PackageCollectionsModel.PackageCollection.PackageVersion in
                let targets = (0 ..< Int.random(in: 1 ... 5)).map {
                    PackageCollectionsModel.PackageTarget(name: "package-\(packageIndex)-target-\($0)",
                                                          moduleName: "module-package-\(packageIndex)-target-\($0)")
                }
                let products = (0 ..< Int.random(in: 1 ... 3)).map {
                    PackageCollectionsModel.PackageProduct(name: "package-\(packageIndex)-product-\($0)",
                                                           type: .executable,
                                                           targets: targets)
                }
                return PackageCollectionsModel.PackageCollection.PackageVersion(version: TSCUtility.Version(versionIndex, 0, 0),
                                                                                packageName: "package-\(packageIndex)",
                                                                                targets: targets,
                                                                                products: products,
                                                                                toolsVersion: .currentToolsVersion,
                                                                                verifiedPlatforms: nil,
                                                                                verifiedSwiftVersions: nil,
                                                                                license: nil)
            }

            return PackageCollectionsModel.PackageCollection.Package(repository: RepositorySpecifier(url: "https://package-\(packageIndex)"),
                                                                     summary: "package \(packageIndex) description",
                                                                     versions: versions,
                                                                     readmeURL: nil)
        }

        return PackageCollectionsModel.PackageCollection(source: .feed(URL(string: "https://feed-\(collectionIndex)")!),
                                                         name: "collection \(collectionIndex)",
                                                         description: "collection \(collectionIndex) description",
                                                         keywords: nil,
                                                         packages: packages,
                                                         createdAt: Date())
    }
}
