/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Closable entity is one that manages underlying resources and needs to be closed for cleanup
/// The intent of this method is for the sole owner of the refernece/handle of the resource to close it completely, comapred to releasing a shared resource.
public protocol Closable {
    func close() throws
}
