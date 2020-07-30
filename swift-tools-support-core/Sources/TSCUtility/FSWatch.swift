/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import Dispatch
import Foundation
import TSCLibc

/// FSWatch is a cross-platform filesystem watching utility.
public class FSWatch {

    public typealias EventReceivedBlock = (_ paths: [AbsolutePath]) -> Void

    /// Delegate for handling events from the underling watcher.
    fileprivate struct _WatcherDelegate {
        let block: EventReceivedBlock

        func pathsDidReceiveEvent(_ paths: [AbsolutePath]) {
            block(paths)
        }
    }

    /// The paths being watched.
    public let paths: [AbsolutePath]

    /// The underlying file watching utility.
    ///
    /// This is FSEventStream on macOS and inotify on linux.
    private var _watcher: _FileWatcher!

    /// The number of seconds the watcher should wait before passing the
    /// collected events to the clients.
    let latency: Double

    /// Create an instance with given paths.
    ///
    /// Paths can be files or directories. Directories are watched recursively.
    public init(paths: [AbsolutePath], latency: Double = 1, block: @escaping EventReceivedBlock) {
        precondition(!paths.isEmpty)
        self.paths = paths
        self.latency = latency

      #if canImport(Glibc)
        var ipaths: [AbsolutePath: Inotify.WatchOptions] = [:]

        // FIXME: We need to recurse here.
        for path in paths {
            if localFileSystem.isDirectory(path) {
                ipaths[path] = .defaultDirectoryWatchOptions
            } else if localFileSystem.isFile(path) {
                ipaths[path] = .defaultFileWatchOptions
                // Watch files.
            } else {
                // FIXME: Report errors
            }
        }

        self._watcher = Inotify(paths: ipaths, latency: latency, delegate: _WatcherDelegate(block: block))
      #elseif os(macOS)
        self._watcher = FSEventStream(paths: paths, latency: latency, delegate: _WatcherDelegate(block: block))
      #else
        fatalError("Unsupported platform")
      #endif
    }

    /// Start watching the filesystem for events.
    ///
    /// This method should be called only once.
    public func start() throws {
        // FIXME: Write precondition to ensure its called only once.
        try _watcher.start()
    }

    /// Stop watching the filesystem. 
    ///
    /// This method should be called after start() and the object should be thrown away.
    public func stop() {
        // FIXME: Write precondition to ensure its called after start() and once only.
        _watcher.stop()
    }
}

/// Protocol to which the different file watcher implementations should conform.
private protocol _FileWatcher {
    func start() throws
    func stop()
}

#if canImport(Glibc)
extension FSWatch._WatcherDelegate: InotifyDelegate {}
extension Inotify: _FileWatcher{}
#elseif os(macOS)
extension FSWatch._WatcherDelegate: FSEventStreamDelegate {}
extension FSEventStream: _FileWatcher{}
#endif

// MARK:- inotify

#if canImport(Glibc)

/// The delegate for receiving inotify events.
public protocol InotifyDelegate {
    func pathsDidReceiveEvent(_ paths: [AbsolutePath])
}

/// Bindings for inotify C APIs.
public final class Inotify {

    /// The errors encountered during inotify operations.
    public enum Error: Swift.Error {
        case invalidFD
        case failedToWatch(AbsolutePath)
    }

    /// The available options for a particular path.
    public struct WatchOptions: OptionSet {
        public let rawValue: Int32

        public init(rawValue: Int32) {
            self.rawValue = rawValue
        }

        // File/directory created in watched directory (e.g., open(2)
        // O_CREAT, mkdir(2), link(2), symlink(2), bind(2) on a UNIX
        // domain socket).
        public static let create = WatchOptions(rawValue: IN_CREATE)

        // File/directory deleted from watched directory.
        public static let delete = WatchOptions(rawValue: IN_DELETE)

        // Watched file/directory was itself deleted.  (This event
        // also occurs if an object is moved to another filesystem,
        // since mv(1) in effect copies the file to the other
        // filesystem and then deletes it from the original filesys‐
        // tem.)  In addition, an IN_IGNORED event will subsequently
        // be generated for the watch descriptor.
        public static let deleteSelf = WatchOptions(rawValue: IN_DELETE_SELF)

        public static let move = WatchOptions(rawValue: IN_MOVE)

        /// Watched file/directory was itself moved.
        public static let moveSelf = WatchOptions(rawValue: IN_MOVE_SELF)

        /// File was modified (e.g., write(2), truncate(2)).
        public static let modify = WatchOptions(rawValue: IN_MODIFY)

        // File or directory was opened.
        public static let open = WatchOptions(rawValue: IN_OPEN)

        // Metadata changed—for example, permissions (e.g.,
        // chmod(2)), timestamps (e.g., utimensat(2)), extended
        // attributes (setxattr(2)), link count (since Linux 2.6.25;
        // e.g., for the target of link(2) and for unlink(2)), and
        // user/group ID (e.g., chown(2)).
        public static let attrib = WatchOptions(rawValue: IN_ATTRIB)

        // File opened for writing was closed.
        public static let closeWrite = WatchOptions(rawValue: IN_CLOSE_WRITE)

        // File or directory not opened for writing was closed.
        public static let closeNoWrite = WatchOptions(rawValue: IN_CLOSE_NOWRITE)

        // File was accessed (e.g., read(2), execve(2)).
        public static let access = WatchOptions(rawValue: IN_ACCESS)

        /// The list of default options that can be used for watching files.
        public static let defaultFileWatchOptions: WatchOptions = [.deleteSelf, .moveSelf, .modify]

        /// The list of default options that can be used for watching directories.
        public static let defaultDirectoryWatchOptions: WatchOptions = [.create, .delete, .deleteSelf, .move, .moveSelf]

        /// List of all available events.
        public static let all: [WatchOptions] = [
            .create,
            .delete,
            .deleteSelf,
            .move,
            .moveSelf,
            .modify,
            .open,
            .attrib,
            .closeWrite,
            .closeNoWrite,
            .access,
        ]
    }

    // Sizeof inotify_event + max len of filepath + 1 (for null char).
    private static let eventSize = MemoryLayout<inotify_event>.size + Int(NAME_MAX) + 1

    /// The paths being watched.
    public let paths: [AbsolutePath: WatchOptions]

    /// The delegate.
    private let delegate: InotifyDelegate?

    /// The settle period (in seconds).
    public let settle: Double

    /// Internal properties.
    private var fd: Int32?

    /// The list of watched directories/files.
    private var wds: [Int32: AbsolutePath] = [:]

    /// The queue on which we read the events.
    private let readQueue = DispatchQueue(label: "org.swift.swiftpm.\(Inotify.self).read)")

    /// Callback queue for the delegate.
    private let callbacksQueue = DispatchQueue(label: "org.swift.swiftpm.\(Inotify.self).callback)")

    /// Condition for handling event reporting.
    private var reportCondition = Condition()

    // Should be read or written to using the report condition only.
    private var collectedEvents: [AbsolutePath] = []

    // Should be read or written to using the report condition only.
    private var lastEventTime: Date? = nil

    // Should be read or written to using the report condition only.
    private var cancelled = false

    /// Pipe for waking up the read loop.
    private var cancellationPipe: [Int32] = [0, 0]

    /// Create a inotify instance.
    ///
    /// The paths are not watched recursively.
    public init(paths: [AbsolutePath: WatchOptions], latency: Double, delegate: InotifyDelegate? = nil) {
        self.paths = paths
        self.delegate = delegate
        self.settle = latency
    }

    /// Start the watch operation.
    public func start() throws {

        // All paths need to exist.
        for (path, _) in paths {
            guard localFileSystem.exists(path) else {
                throw Error.failedToWatch(path)
            }
        }
    
        // Create the file descriptor.
        let fd = inotify_init1(Int32(IN_NONBLOCK))

        guard fd != -1 else {
            throw Error.invalidFD
        }
        self.fd = fd
    
        /// Add watch for each path.
        for (path, options) in paths {

            let wd = inotify_add_watch(fd, path.description, UInt32(options.rawValue))
            guard wd != -1 else {
                throw Error.failedToWatch(path)
            }

            self.wds[wd] = path
        }

        // Start the report thread.
        startReportThread()

        readQueue.async {
            self.startRead()
        }
    }

    /// End the watch operation.
    public func stop() {
        // FIXME: Write precondition to ensure this is called only once.
        guard let fd = fd else {
            assertionFailure("end called without a fd")
            return
        }

        // Shutdown the report thread.
        reportCondition.whileLocked {
            cancelled = true
            reportCondition.signal()
        }

        // Wakeup the read loop by writing on the cancellation pipe.
        let writtenData = write(cancellationPipe[1], "", 1)
        assert(writtenData == 1)

        // FIXME: We need to remove the watches.
        close(fd)
    }

    private func startRead() {
        guard let fd = fd else {
            fatalError("unexpected call to startRead without fd")
        }

        // Create a pipe that we can use to get notified when we're cancelled.
        let pipeRv = pipe(&cancellationPipe)
        // FIXME: We don't see pipe2 for some reason.
        let f = fcntl(cancellationPipe[0], F_SETFL, O_NONBLOCK)
        assert(f != -1)
        assert(pipeRv == 0)

        while true {
            // The read fd set. Contains the inotify and cancellation fd.
            var rfds = fd_set()
            FD_ZERO(&rfds)

            FD_SET(fd, &rfds)
            FD_SET(cancellationPipe[0], &rfds)

            let nfds = [fd, cancellationPipe[0]].reduce(0, max) + 1
            // num fds, read fds, write fds, except fds, timeout
            let selectRet = select(nfds, &rfds, nil, nil, nil)
            // FIXME: Check for int signal.
            assert(selectRet != -1)

            // Return if we're cancelled.
            if FD_ISSET(cancellationPipe[0], &rfds) {
                return
            }
            assert(FD_ISSET(fd, &rfds))

            let buf = UnsafeMutablePointer<CChar>.allocate(capacity: Inotify.eventSize)
            // FIXME: We need to free the buffer.

            let readLength = read(fd, buf, Inotify.eventSize)
            // FIXME: Check for int signal.
    
            // Consume events.
            var idx = 0
            while idx < readLength {
                let event = withUnsafePointer(to: &buf[idx]) {
                    $0.withMemoryRebound(to: inotify_event.self, capacity: 1) {
                        $0.pointee
                    }
                }

                // Get the associated with the event.
                var path = wds[event.wd]!

                // FIXME: We need extract information from the event mask and
                // create a data structure.
                // FIXME: Do we need to detect and remove watch for directories
                // that are deleted?

                // Get the relative base name from the event if present.
                if event.len > 0 {
                    // Get the basename of the file that had the event.
                    let basename = String(cString: buf + idx + MemoryLayout<inotify_event>.size)
    
                    // Construct the full path.
                    // FIXME: We should report this path separately.
                    path = path.appending(component: basename)
                }

                // Signal the reporter.
                reportCondition.whileLocked {
                    lastEventTime = Date()
                    collectedEvents.append(path)
                    reportCondition.signal()
                }

                idx += MemoryLayout<inotify_event>.size + Int(event.len)
            }
        }
    }

    /// Spawns a thread that collects events and reports them after the settle period.
    private func startReportThread() {
        let thread = TSCBasic.Thread {
            var endLoop = false
            while !endLoop {

                // Block until we timeout or get signalled.
                self.reportCondition.whileLocked {
                    var performReport = false

                    // Block until timeout expires or wait forever until we get some event.
                    if let lastEventTime = self.lastEventTime {
                        let timeout = lastEventTime + Double(self.settle)
                        let timeLimitReached = !self.reportCondition.wait(until: timeout)

                        if timeLimitReached {
                            self.lastEventTime = nil
                            performReport = true
                        }
                    } else {
                        self.reportCondition.wait()
                    }

                    // If we're cancelled, just return.
                    if self.cancelled {
                        endLoop = true
                        return
                    }

                    // Report the events if we're asked to.
                    if performReport && !self.collectedEvents.isEmpty {
                        let events = self.collectedEvents
                        self.collectedEvents = []
                        self.callbacksQueue.async {
                            self.report(events)
                        }
                    }
                }
            }
        }

        thread.start()
    }

    private func report(_ paths: [AbsolutePath]) {
        delegate?.pathsDidReceiveEvent(paths)
    }
}

// FIXME: <rdar://problem/45794219> Swift should provide shims for FD_ macros

private func FD_ZERO(_ set: inout fd_set) {
      #if os(Android)
	set.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
      #else
	set.__fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
      #endif
}

private func FD_SET(_ fd: Int32, _ set: inout fd_set) {
    let intOffset = Int(fd / 16)
    let bitOffset = Int(fd % 16)
  #if os(Android)
    var fd_bits = set.fds_bits
    let mask: UInt = 1 << bitOffset
  #else
    var fd_bits = set.__fds_bits
    let mask = 1 << bitOffset
  #endif
    switch intOffset {
        case 0: fd_bits.0 = fd_bits.0 | mask
        case 1: fd_bits.1 = fd_bits.1 | mask
        case 2: fd_bits.2 = fd_bits.2 | mask
        case 3: fd_bits.3 = fd_bits.3 | mask
        case 4: fd_bits.4 = fd_bits.4 | mask
        case 5: fd_bits.5 = fd_bits.5 | mask
        case 6: fd_bits.6 = fd_bits.6 | mask
        case 7: fd_bits.7 = fd_bits.7 | mask
        case 8: fd_bits.8 = fd_bits.8 | mask
        case 9: fd_bits.9 = fd_bits.9 | mask
        case 10: fd_bits.10 = fd_bits.10 | mask
        case 11: fd_bits.11 = fd_bits.11 | mask
        case 12: fd_bits.12 = fd_bits.12 | mask
        case 13: fd_bits.13 = fd_bits.13 | mask
        case 14: fd_bits.14 = fd_bits.14 | mask
        case 15: fd_bits.15 = fd_bits.15 | mask
        default: break
    }
  #if os(Android)
    set.fds_bits = fd_bits
  #else
    set.__fds_bits = fd_bits
  #endif
}

private func FD_ISSET(_ fd: Int32, _ set: inout fd_set) -> Bool {
    let intOffset = Int(fd / 32)
    let bitOffset = Int(fd % 32)
  #if os(Android)
    let fd_bits = set.fds_bits
    let mask: UInt = 1 << bitOffset
  #else
    let fd_bits = set.__fds_bits
    let mask = 1 << bitOffset
  #endif
    switch intOffset {
        case 0: return fd_bits.0 & mask != 0
        case 1: return fd_bits.1 & mask != 0
        case 2: return fd_bits.2 & mask != 0
        case 3: return fd_bits.3 & mask != 0
        case 4: return fd_bits.4 & mask != 0
        case 5: return fd_bits.5 & mask != 0
        case 6: return fd_bits.6 & mask != 0
        case 7: return fd_bits.7 & mask != 0
        case 8: return fd_bits.8 & mask != 0
        case 9: return fd_bits.9 & mask != 0
        case 10: return fd_bits.10 & mask != 0
        case 11: return fd_bits.11 & mask != 0
        case 12: return fd_bits.12 & mask != 0
        case 13: return fd_bits.13 & mask != 0
        case 14: return fd_bits.14 & mask != 0
        case 15: return fd_bits.15 & mask != 0
        default: return false
    }
}

#endif

// MARK:- FSEventStream

#if os(macOS)

private func callback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    let eventStream = unsafeBitCast(clientCallBackInfo, to: FSEventStream.self)

    // We expect the paths to be reported in an NSArray because we requested CFTypes.
    let eventPaths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []

    // Compute the set of paths that were changed.
    let paths = eventPaths.map({ AbsolutePath($0) })

    eventStream.callbacksQueue.async {
        eventStream.delegate.pathsDidReceiveEvent(paths)
    }
}

public protocol FSEventStreamDelegate {
    func pathsDidReceiveEvent(_ paths: [AbsolutePath])
}

/// Wrapper for Darwin's FSEventStream API.
public final class FSEventStream {

    /// The errors encountered during fs event watching.
    public enum Error: Swift.Error {
        case unknownError
    }

    /// Reference to the underlying event stream.
    ///
    /// This is var and implicitly unwrapped optional because
    /// we need to capture self for the context.
    private var stream: FSEventStreamRef!

    /// Reference to the handler that should be called.
    let delegate: FSEventStreamDelegate

    /// The thread on which the stream is running.
    private var thread: TSCBasic.Thread?

    /// The run loop attached to the stream.
    private var runLoop: CFRunLoop?

    /// Callback queue for the delegate.
    fileprivate let callbacksQueue = DispatchQueue(label: "org.swift.swiftpm.\(FSEventStream.self).callback)")

    public init(
        paths: [AbsolutePath],
        latency: Double,
        delegate: FSEventStreamDelegate,
        flags: FSEventStreamCreateFlags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
    ) {
        self.delegate = delegate

        // Create the context that needs to be passed to the callback.
        var callbackContext = FSEventStreamContext()
        callbackContext.info = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)

        // Create the stream.
        self.stream = FSEventStreamCreate(nil,
            callback, 
            &callbackContext, 
            paths.map({ $0.pathString }) as CFArray, 
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )
    }

    // Start the runloop.
    public func start() throws {
        let thread = Thread { [weak self] in
            guard let `self` = self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            // Schedule the run loop.
            FSEventStreamScheduleWithRunLoop(
                self.stream,
                CFRunLoopGetCurrent(),
                CFRunLoopMode.defaultMode.rawValue
            )

            // Start the stream.
            FSEventStreamScheduleWithRunLoop(self.stream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(self.stream)
            CFRunLoopRun()

            // Perform cleanup.
            FSEventStreamStop(self.stream)
            FSEventStreamUnscheduleFromRunLoop(self.stream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamInvalidate(self.stream)
            FSEventStreamRelease(self.stream)
        }
        thread.start()
		self.thread = thread
    }

    /// Stop watching the events.
    public func stop() {
        // FIXME: This is probably not thread safe?
        if let runLoop = self.runLoop {
            CFRunLoopStop(runLoop)
        }
    }
}
#endif
