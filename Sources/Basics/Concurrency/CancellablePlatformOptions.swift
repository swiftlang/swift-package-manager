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

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import Subprocess
#else
internal import Subprocess
#endif

extension PlatformOptions {
    /// Options for a child process run through `Cancellator.withCancellable`.
    ///
    /// Without these, cancelling terminates only the direct child with an immediate `SIGKILL`: descendants (for example the
    /// `zip` started by `sh -c`) survive, and the child gets no chance to clean up. This puts the child in its own
    /// process group, as `AsyncProcess` did, and tears the whole group down gracefully before force-terminating it.
    ///
    /// Keep in sync with the copy in `SwiftTestCommand.swift`.
    static var cancellable: PlatformOptions {
        var options = PlatformOptions()
        #if os(Windows)
        options.createProcessGroup = true
        options.teardownSequence = [.gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: .seconds(2))]
        #else
        options.processGroupID = 0
        options.teardownSequence = [
            .send(signal: .interrupt, toProcessGroup: true, allowedDurationToNextStep: .seconds(2)),
        ]
        #endif
        return options
    }
}
