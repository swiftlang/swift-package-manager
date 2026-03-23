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

package enum WarningControlFlags {
    package static func filterSwiftWarningControlFlags(_ args: [String]) -> [String] {
        var filtered: [String] = []
        var skipNextArg = false

        for arg in args {
            if skipNextArg {
                skipNextArg = false
                continue
            }

            switch arg {
            case "-warnings-as-errors", "-no-warnings-as-errors":
                break
            case "-Wwarning", "-Werror":
                skipNextArg = true
            default:
                filtered.append(arg)
            }
        }
        return filtered
    }

    package static func filterClangWarningControlFlags(_ args: [String]) -> [String] {
        args.filter { arg in
            // Filter out warning control flags:
            // -Wxxxx
            // -Wno-xxxx
            // -Werror
            // -Werror=xxxx
            // -Wno-error
            // -Wno-error=xxxx
            arg.count <= 2 || !arg.starts(with: "-W")
        }
    }
}
