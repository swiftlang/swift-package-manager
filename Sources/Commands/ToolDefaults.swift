/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import Utility
import POSIX

struct ToolDefaults {
#if Xcode
    // when in Xcode we are built with same toolchain as we will run
    // this is not a production ready mode

    static let SWIFT_EXEC = getenv("SWIFT_EXEC")!.abspath
    static let llbuild = Path.join(getenv("SWIFT_EXEC")!, "../swift-build-tool").abspath
    static let libdir = argv0.parentDirectory
#else
    static let SWIFT_EXEC = Path.join(argv0, "../swiftc").abspath
    static let llbuild = Path.join(argv0, "../swift-build-tool").abspath
    static let libdir = Path.join(argv0, "../../lib/swift/pm").abspath
#endif
}
