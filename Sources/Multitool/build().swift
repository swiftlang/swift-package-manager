/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.getenv
import Utility

public func build(YAMLPath YAMLPath: String, target: String) throws {
    var args = [swift_build_tool(), "-f", YAMLPath, target]
    if verbosity != .Concise { args.append("-v") }
    try system(args)
}

private func swift_build_tool() -> String {
    if let tool = getenv("SWIFT_BUILD_TOOL") {  //FIXME remove and if people complain, make it a flag
        return tool
    } else if let path = try? Path.join(exepath, "..", "swift-build-tool").abspath() where path.isFile {
        return path
    } else {
        return Toolchain.which("swift-build-tool")
    }
}

private let exepath: String = try! Process.arguments.first!.abspath()
