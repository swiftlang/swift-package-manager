//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

#if canImport(Glibc) || canImport(Musl) || canImport(Android)
// This is a lazily initialised global variable that when read for the first time, will ignore SIGPIPE.
private let globallyIgnoredSIGPIPE: Bool = {
  /* no F_SETNOSIGPIPE on Linux :( */
  _ = signal(SIGPIPE, SIG_IGN)
  return true
}()
#endif

/// We receive a `SIGPIPE` if we write to a pipe that points to a crashed process. This in particular happens if the
/// target of a `JSONRPCConnection` has crashed and we try to send it a message or if swift-format crashes and we try
/// to send the source file to it.
///
/// On Darwin, `DispatchIO` ignores `SIGPIPE` for the pipes handled by it and swift-tools-support-core offers
/// `LocalFileOutputByteStream.disableSigpipe`, but that features is not available on Linux.
///
/// Instead, globally ignore `SIGPIPE` on Linux to prevent us from crashing if the `JSONRPCConnection`'s target crashes.
///
/// On Darwin platforms and on Windows this is a no-op.
package func globallyDisableSigpipeIfNeeded() {
  #if !canImport(Darwin) && !os(Windows)
  let haveWeIgnoredSIGPIEThisIsHereToTriggerIgnoringIt = globallyIgnoredSIGPIPE
  guard haveWeIgnoredSIGPIEThisIsHereToTriggerIgnoringIt else {
    fatalError("globallyIgnoredSIGPIPE should always be true")
  }
  #endif
}
