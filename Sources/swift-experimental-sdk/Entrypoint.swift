//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftSDKCommand
import Foundation

@main
struct Entrypoint {
    static func main() async {
        fputs("warning: `swift experimental-sdk` command is deprecated and will be removed in a future version of SwiftPM. Use `swift sdk` instead.\n", stderr)
        await SwiftSDKCommand.main()
    }
}
