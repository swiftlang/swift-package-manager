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

import Foundation

import struct SPMBuildCore.BuildSystemProvider
import struct Basics.Diagnostic
import CoreCommands  // for Basics.Diagnostic.deprecatedBuildSystem()
package let warningbuildingButLinkingDifferentVersionRegex = try! Regex(#"ld: warning: building for .*, but linking with dylib '.*' which was built for newer version \d+(.\d+)?"#)
package let warningRefToTypeBrokenRegex = try! Regex(#"warning: reference to type '.*' broken by a context change; '.*' was expected to be in \'.*', but now a candidate is found only in '.*'"#)

package func filterWarnings(content: String) -> [String] {
    return filterSwiftPMOutput(content: content, filterLevel: .warning)
}

public enum LogLevelFilter: String {
    case warning
    case error
}

public func filterSwiftPMOutput(
    content: String,
    filterLevel: LogLevelFilter? = nil,
) -> [String] {
    var contentArray = content.split(separator: "\n")

    if let filterLevel {
        contentArray = contentArray.filter {
            $0.contains(filterLevel.rawValue)
        }
    }

    contentArray = contentArray
        .filter { !$0.contains("[logging]") }
        .filter { !$0.contains("Unable to locate libSwiftScan") }
        .filter { !($0.contains("warning: ") && $0.contains("unable to find libclang")) }
        .filter { !$0.contains(warningbuildingButLinkingDifferentVersionRegex) }
        .filter { !$0.contains(warningRefToTypeBrokenRegex) }
        .filter {
                !$0.contains(Basics.Diagnostic.deprecatedBuildSystem(buildSystem: .native).message)
        }
        .filter {
                !$0.contains(Basics.Diagnostic.deprecatedBuildSystem(buildSystem: .xcode).message)
        }

    return contentArray.map { String($0) }
}
