//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import TSCBasic
import class TSCUtility.FSWatch

final public class FileWatcher {
    private let fileSystem: FileSystem
    private let path: AbsolutePath

    private var fswatch: FSWatch?

    private var content: ByteString?
    private let lock: Lock = Lock()

    public init(path: AbsolutePath, fileSystem: FileSystem) {
        self.fileSystem = fileSystem
        self.path = resolveSymlinks(path)
    }

    deinit {
        self.stop()
    }

    public func start(handler: @escaping () -> ()) throws {
        guard (self.lock.withLock { self.fswatch }) == nil else {
            throw InternalError("FileWatcher on \(self.path) already in place")
        }

        let fswatchHandler = { (changedLocations: [AbsolutePath]) in
            // check if the file has changed
            guard changedLocations.contains(where: { $0 == self.path || $0 == self.path.parentDirectory }) else {
                return
            }

            // compare content
            let fileContent = try? self.fileSystem.readFileContents(self.path)
            self.lock.withLock {
                if self.content != fileContent {
                    self.content = fileContent
                    handler()
                }
            }
        }

        try self.lock.withLock {
            if self.fileSystem.exists(self.path) {
                self.content = try? self.fileSystem.readFileContents(self.path)
            }
            self.fswatch = FSWatch(paths: [self.path.parentDirectory], latency: 1, block: fswatchHandler)
            try self.fswatch?.start()
        }
    }

    public func stop() {
        self.lock.withLock {
            self.fswatch?.stop()
            self.fswatch = nil
        }
    }
}
