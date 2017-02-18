/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageLoading
import POSIX

struct ToolDefaults: ManifestResourceProvider {

    var swiftCompilerPath: AbsolutePath {
        return toolchain.swiftCompiler
    }

    var libraryPath: AbsolutePath {
        return toolchain.libDir
    }

    let toolchain: UserToolchain

    init(_ toolchain: UserToolchain) {
        self.toolchain = toolchain
    }
}
