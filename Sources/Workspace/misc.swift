/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import PackageModel
import PackageGraph

extension ManagedDependency {
    public var checkoutState: CheckoutState? {
        if case .checkout(let checkoutState) = state {
            return checkoutState
        }
        return nil
    }
}

extension PinsStore {
    /// Pin a managed dependency at its checkout state.
    ///
    /// This method does nothing if the dependency is in edited state.
    func pin(_ dependency: ManagedDependency) {

        // Get the checkout state.
        let checkoutState: CheckoutState
        switch dependency.state {
        case .checkout(let state):
            checkoutState = state
        case .edited, .local:
            return
        }

        self.pin(
            packageRef: dependency.packageRef,
            state: checkoutState)
    }
}

/// A file watcher utility for the Package.resolved file.
///
/// This is not intended to be used directly by clients.
final class ResolvedFileWatcher {
    private var fswatch: FSWatch!
    private var existingValue: ByteString?
    private let valueLock: Lock = Lock()
    private let resolvedFile: AbsolutePath

    public func updateValue() {
        valueLock.withLock {
            self.existingValue = try? localFileSystem.readFileContents(resolvedFile)
        }
    }

    init(resolvedFile: AbsolutePath, onChange: @escaping () -> ()) throws {
        self.resolvedFile = resolvedFile

        let block = { [weak self] (paths: [AbsolutePath]) in
            guard let self = self else { return }

            // Check if resolved file is part of the received paths.
            let hasResolvedFile = paths.contains{ $0.appending(component: resolvedFile.basename) == resolvedFile }
            guard hasResolvedFile else { return }

            self.valueLock.withLock {
                // Compute the contents of the resolved file and fire the onChange block
                // if its value is different than existing value.
                let newValue = try? localFileSystem.readFileContents(resolvedFile)
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
