//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCLibc
#if os(Windows)
import CRT
#endif

import protocol TSCBasic.WritableByteStream

extension TerminalCapabilities {
  static func interactive(
    stream: WritableByteStream,
    environment: Environment
  ) -> Bool {
    // Explicitly disabled colors via TERM == dumb
    if environment.termInteractive == false { return false }
    // Interactive if underlying stream is a tty.
    return stream.isTTY
  }
}

extension Environment {
  /// The interactivity enabled by the `"TERM"` environment variable.
  var termInteractive: Bool? {
    switch self["TERM"] {
    case "dumb": false
    default: nil
    }
  }
}
