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
    package static func containsWarningsAsErrors(_ args: [String]) -> Bool {
        args.contains("-warnings-as-errors")
    }

    package static func filterSwiftWarningControlFlags(_ args: [String]) -> [String] {
        self.filterSwiftWarningControlFlags(args, value: { $0 })
    }

    package static func filterSwiftWarningControlFlags<Element>(
        _ args: [Element],
        value: (Element) -> String
    ) -> [Element] {
        self.splitSwiftWarningControlFlags(args, value: value).other
    }

    package static func extractSwiftWarningControlFlags(_ args: [String]) -> [String] {
        self.splitSwiftWarningControlFlags(args, value: { $0 }).warningControl
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

    package static func splitSwiftWarningControlFlags<Element>(
        _ args: [Element],
        value: (Element) -> String
    ) -> (warningControl: [Element], other: [Element]) {
        var warningControl: [Element] = []
        var other: [Element] = []
        var captureNextArg = false

        for arg in args {
            if captureNextArg {
                captureNextArg = false
                warningControl.append(arg)
                continue
            }

            switch value(arg) {
            case "-warnings-as-errors", "-no-warnings-as-errors":
                warningControl.append(arg)
            case "-Wwarning", "-Werror":
                warningControl.append(arg)
                captureNextArg = true
            default:
                other.append(arg)
            }
        }
        return (warningControl, other)
    }
}
