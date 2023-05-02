//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import class Foundation.NSLock
import PackageModel
import PackageGraph

import struct TSCBasic.ByteString

import class TSCUtility.FSWatch

/// A file watcher utility for the Package.resolved file.
///
/// This is not intended to be used directly by clients.
final class ResolvedFileWatcher {
    private var fswatch: FSWatch!
    private var existingValue: ByteString?
    private let valueLock = NSLock()
    private let resolvedFile: TSCAbsolutePath

    public func updateValue() {
        valueLock.withLock {
            self.existingValue = try? localFileSystem.readFileContents(resolvedFile)
        }
    }

    init(resolvedFile: AbsolutePath, onChange: @escaping () -> ()) throws {
        let resolvedFile = TSCAbsolutePath(resolvedFile)
        self.resolvedFile = resolvedFile

        let block = { [weak self] (paths: [TSCAbsolutePath]) in
            guard let self else { return }

            // Check if resolved file is part of the received paths.
            let hasResolvedFile = paths.contains{ $0.appending(component: resolvedFile.basename) == resolvedFile }
            guard hasResolvedFile else { return }

            self.valueLock.withLock {
                // Compute the contents of the resolved file and fire the onChange block
                // if its value is different than existing value.
                let newValue: ByteString? = try? localFileSystem.readFileContents(resolvedFile)
                if self.existingValue != newValue {
                    self.existingValue = newValue
                    onChange()
                }
            }
        }

        fswatch = FSWatch(paths: [resolvedFile.parentDirectory], latency: 1, block: block)
        try fswatch.start()
    }

    deinit {
        fswatch.stop()
    }
}
