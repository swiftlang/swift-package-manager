//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import SwiftIfConfig
import TSCUtility
import Foundation

extension StaticBuildConfiguration {
    public static func getHostConfiguration(
        usingSwiftCompiler swiftCompiler: AbsolutePath,
        extraManifestFlags: [String],
    ) throws -> StaticBuildConfiguration {
        // Call the compiler to get the static build configuration JSON.
        let compilerOutput: String
        do {
            let args = [swiftCompiler.pathString, "-frontend", "-print-static-build-config"] + extraManifestFlags
            let result = try AsyncProcess.popen(arguments: args)
            compilerOutput = try result.utf8Output()
        } catch {
            throw InternalError("Failed to get target info (\(error.interpolationDescription))")
        }

        // Parse the compiler's JSON output.
        guard let outputData = compilerOutput.data(using: .utf8) else {
            throw InternalError("Failed to get data from compiler output for static build configuration: \(compilerOutput)")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(StaticBuildConfiguration.self, from: outputData)
    }
}
