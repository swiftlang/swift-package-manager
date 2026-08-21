//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// A registered client's public name.
public struct ClientID: Hashable, Sendable {
    /// The id's textual form, as it appears on the wire.
    public let value: String

    /// Creates an id from its textual form.
    ///
    /// - Parameter value: The id as minted by ``ClientIDGenerator`` or received
    ///   from a client.
    public init(_ value: String) {
        self.value = value
    }
}
