//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class TSCBasic.LocalFileOutputByteStream
import class TSCBasic.TerminalController
import class TSCBasic.ThreadSafeOutputByteStream
import protocol TSCBasic.WritableByteStream

extension WritableByteStream {
    /// Returns true if an only if the output byte stream is attached to a TTY.
    public var isTTY: Bool {
        let stream: WritableByteStream
        if let threadSafeStream = self as? ThreadSafeOutputByteStream {
            stream = threadSafeStream.stream
        } else {
            stream = self
        }
        guard let fileStream = stream as? LocalFileOutputByteStream else {
            return false
        }
        return TerminalController.isTTY(fileStream)
    }
}
