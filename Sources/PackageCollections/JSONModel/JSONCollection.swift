/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

public enum JSONPackageCollectionModel {}

extension JSONPackageCollectionModel {
    /// Representation of `PackageCollection` JSON schema version
    public enum FormatVersion: String, Codable {
        case v1_0 = "1.0"
    }
}
