// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors

import Foundation
import PackagePlugin

@main
struct GenerateSymbolGraphPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        for target in context.package.targets where target is SwiftSourceModuleTarget {
            let _ = try packageManager.getSymbolGraph(for: target, options: .init())
        }
    }
}
