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
import Commands
import SwiftSDKTool
import PackageCollectionsTool
import PackageRegistryTool

let firstArg = CommandLine.arguments[0]
let baseNameWithoutExtension = (try? AbsolutePath(validating: firstArg).basenameWithoutExt) ??
    (try? RelativePath(validating: firstArg).basenameWithoutExt)

@main
struct SwiftPM {
    static func main() async {
        await main(execName: baseNameWithoutExtension)
    }

    @discardableResult
    private static func main(execName: String?) async -> Bool {
        switch execName {
        case "swift-package":
            await SwiftPackageTool.main()
        case "swift-build":
            await SwiftBuildTool.main()
        case "swift-experimental-sdk":
            await SwiftSDKTool.main()
        case "swift-test":
            SwiftTestTool.main()
        case "swift-run":
            SwiftRunTool.main()
        case "swift-package-collection":
            await SwiftPackageCollectionsTool.main()
        case "swift-package-registry":
            await SwiftPackageRegistryTool.main()
        default:
            // Workaround a bug in Swift 5.9, where multiple executables with an `async` main entrypoint can't be linked
            // into the same test bundle. We're then linking single `swift-package-manager` binary instead and passing
            // executable name via `SWIFTPM_EXEC_NAME`.
            if await !main(execName: EnvironmentVariables.process()["SWIFTPM_EXEC_NAME"]) {
                fatalError("swift-package-manager launched with unexpected name: \(execName ?? "(unknown)")")
            }
        }

        return true
    }
}
