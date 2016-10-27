/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc

/// The single shared signal manager object, this is initialized here and not in class because we want to reference it from a C function pointer.
private let sharedSignalManager = SignalManager()

/// The old sigaction to chain the handlers of signals.
private var oldAction = sigaction()

/// A class to manage POSIX signals.
public final class SignalManager {
    /// The call back type which clients can register.
    public typealias SignalCallback = () -> Void

    /// The shared signal manager instance.
    public static var shared: SignalManager {
        return sharedSignalManager
    }

    /// The type of supported singals.
    public enum Signal {
        /// User signal one.
        case usr1

        /// User signal two.
        case usr2
    }

    fileprivate init() {
        // Register our signals.
        SignalManager.register(.usr1)
        SignalManager.register(.usr2)
    }

    /// Dictionary to hold the signal to callbacks mapping.
    private var callbacksMap: [Signal: [SignalCallback]] = [:]

    /// Register callback for a signal, the callback will be executed once when the next matching signal
    /// is received and then freed.
    public func register(_ signal: Signal, callback: @escaping SignalCallback) {
        var callbacks = callbacksMap[signal] ?? []
        callbacks.append(callback)
        callbacksMap[signal] = callbacks
    }

    /// This method is called when a signal is received.
    private func received(signal: Signal) {
        // Check if we have any registered callbacks.
        guard let signalCallbacks = callbacksMap[signal] else { return }
        // Execute all the callbacks.
        signalCallbacks.forEach { $0() }
        // Remove the callbacks.
        callbacksMap[signal] = nil
    }

    /// Raise a signal.
    public func raise(_ signal: Signal) {
        _ = libc.raise(signal.rawValue)
    }

    /// Registers a signal, call this only once per signal to avoid handler being called multiple times.
    private static func register(_ signal: Signal) {
        // Get the old action.
        oldAction = sigaction()
        sigaction(signal.rawValue, nil, &oldAction)

        // Create new action.
        var action = sigaction()
        action.__sigaction_u.__sa_handler = { sig in 
            // Call the old Manager if any.
            if let oldManager = oldAction.__sigaction_u.__sa_handler {
                oldManager(sig)
            }
            if let signal = Signal(rawValue: sig) {
                sharedSignalManager.received(signal: signal)
            }
        }
        // Set the new action.
        sigaction(signal.rawValue, &action, nil)
    }
    
}

private extension SignalManager.Signal {
    /// Returns the raw value of signal.
    var rawValue: Int32 {
        switch self {
        case .usr1: return SIGUSR1
        case .usr2: return SIGUSR2
        }
    }

    /// Create a signal object from raw value.
    init?(rawValue: Int32) {
        switch rawValue {
        case SIGUSR1: self = .usr1
        case SIGUSR2: self = .usr2
        default: return nil
        }
    }
}
