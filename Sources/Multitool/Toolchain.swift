/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import PackageType
import Utility
import POSIX

#if Xcode

    // when in Xcode we are built with same toolchain as we will run
    // this is not a production ready mode

    public let SWIFT_EXEC = getenv("SWIFT_EXEC")!.abspath()
    public let llbuild = Path.join(getenv("SWIFT_EXEC")!, "../swift-build-tool").abspath()
    public let libdir = Process.arguments.first!.parentDirectory
#else
    public let SWIFT_EXEC = Path.join(Process.arguments.first!, "../swiftc").abspath()
    public let llbuild = Path.join(Process.arguments.first!, "../swift-build-tool").abspath()
    public let libdir = Path.join(Process.arguments.first!, "../../lib/swift/pm").abspath()
#endif
