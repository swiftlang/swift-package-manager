//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// An event that alters the card stack after some input from the user.
enum CardEvent {
    /// Pop the top card from the stack, providing an optional error that
    /// may have occurred.
    case pop(Swift.Error? = nil)

    /// Push a new card onto the stack.
    case push(Card)

    /// Quit the program, providing an optional error that may have occurred.
    case quit(Swift.Error? = nil)
}
