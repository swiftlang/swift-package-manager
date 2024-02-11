//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class TSCBasic.TerminalController
import protocol TSCBasic.WritableByteStream

/// A single line percent-based progress animation.
final class SingleLinePercentProgressAnimation: ProgressAnimationProtocol {
    private let stream: WritableByteStream
    private let header: String?
    private var displayedPercentages: Set<Int> = []
    private var hasDisplayedHeader = false

    init(stream: WritableByteStream, header: String?) {
        self.stream = stream
        self.header = header
    }

    func update(step: Int, total: Int, text: String) {
        if let header = header, !hasDisplayedHeader {
            stream.send(header)
            stream.send("\n")
            stream.flush()
            hasDisplayedHeader = true
        }

        let percentage = step * 100 / total
        let roundedPercentage = Int(Double(percentage / 10).rounded(.down)) * 10
        if percentage != 100, !displayedPercentages.contains(roundedPercentage) {
            stream.send(String(roundedPercentage)).send(".. ")
            displayedPercentages.insert(roundedPercentage)
        }

        stream.flush()
    }

    func complete(success: Bool) {
        if success {
            stream.send("OK")
            stream.flush()
        }
    }

    func clear() {
    }
}
