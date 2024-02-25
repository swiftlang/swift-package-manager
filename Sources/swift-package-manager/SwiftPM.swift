//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

@_spi(SwiftPMInternal)
import Commands

import SwiftSDKCommand
import PackageCollectionsCommand
import PackageRegistryCommand

let firstArg = CommandLine.arguments[0]
let execName = (try? AbsolutePath(validating: firstArg).basenameWithoutExt) ??
    (try? RelativePath(validating: firstArg).basenameWithoutExt)

@main
struct SwiftPM {
    static func main() async {
        switch execName {
        case "swift-package":
            await SwiftPackageCommand.main()
        case "swift-build":
            SwiftBuildCommand.main()
        case "swift-experimental-sdk":
            await SwiftSDKCommand.main()
        case "swift-test":
            SwiftTestCommand.main()
        case "swift-run":
            SwiftRunCommand.main()
        case "swift-package-collection":
            await PackageCollectionsCommand.main()
        case "swift-package-registry":
            await PackageRegistryCommand.main()
        default:
            fatalError("swift-package-manager launched with unexpected name: \(execName ?? "(unknown)")")
        }
    }
}
