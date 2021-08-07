/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public struct Configuration {
    public var resolution: Resolution
    public var manifestsLoading: ManifestsLoading
    public var mirrors: Mirrors
    public var netrc: Netrc
    public var collections: Collections

    public init(resolution: Resolution,
                manifestsLoading: ManifestsLoading,
                mirrors: Mirrors,
                netrc: Netrc,
                collections: Collections) {
        self.resolution = resolution
        self.manifestsLoading = manifestsLoading
        self.mirrors = mirrors
        self.netrc = netrc
        self.collections = collections
    }
}
