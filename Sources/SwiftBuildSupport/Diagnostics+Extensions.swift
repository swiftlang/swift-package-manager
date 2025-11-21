//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

extension Basics.Diagnostic {
    package static var swiftBackDeployWarning: Self {
        .warning(
            """
            Swift compiler no longer supports statically linking the Swift libraries. They're included in the OS by \
            default starting with macOS Mojave 10.14.4 beta 3. For macOS Mojave 10.14.3 and earlier, there's an \
            optional "Swift 5 Runtime Support for Command Line Tools" package that can be downloaded from \"More Downloads\" \
            for Apple Developers at https://developer.apple.com/download/more/
            """
        )
    }
}
