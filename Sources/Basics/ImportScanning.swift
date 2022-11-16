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

import Dispatch

import class Foundation.JSONDecoder
import struct TSCBasic.AbsolutePath
import class TSCBasic.Process

private let defaultImports = ["Swift", "SwiftOnoneSupport", "_Concurrency", "_StringProcessing"]

private struct Imports: Decodable {
    let imports: [String]
}

public protocol ImportScanner {
    func scanImports(_ filePathToScan: AbsolutePath, callbackQueue: DispatchQueue, completion: @escaping (Result<[String], Error>) -> Void)
}

public struct SwiftcImportScanner: ImportScanner {
    private let swiftCompilerEnvironment: EnvironmentVariables
    private let swiftCompilerFlags: [String]
    private let swiftCompilerPath: AbsolutePath

    public init(swiftCompilerEnvironment: EnvironmentVariables, swiftCompilerFlags: [String], swiftCompilerPath: AbsolutePath) {
        self.swiftCompilerEnvironment = swiftCompilerEnvironment
        self.swiftCompilerFlags = swiftCompilerFlags
        self.swiftCompilerPath = swiftCompilerPath
    }

    public func scanImports(_ filePathToScan: AbsolutePath,
                            callbackQueue: DispatchQueue,
                            completion: @escaping (Result<[String], Error>) -> Void) {
        let cmd = [swiftCompilerPath.pathString,
                   filePathToScan.pathString,
                   "-scan-dependencies", "-Xfrontend", "-import-prescan"] + self.swiftCompilerFlags

        TSCBasic.Process.popen(arguments: cmd, environment: self.swiftCompilerEnvironment, queue: callbackQueue) { result in
            dispatchPrecondition(condition: .onQueue(callbackQueue))
            
            do {
                let stdout = try result.get().utf8Output()
                let imports = try JSONDecoder.makeWithDefaults().decode(Imports.self, from: stdout).imports
                    .filter { !defaultImports.contains($0) }
                
                callbackQueue.async {
                    completion(.success(imports))
                }
            } catch {
                callbackQueue.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
