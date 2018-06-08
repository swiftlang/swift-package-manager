/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

#if canImport(os)
import os.log
import os.signpost
#endif

// MARK :- OSLog APIs

/// A custom log object that can be passed to logging functions in order to send
/// messages to the logging system.
///
/// This is a thin wrapper for Darwin's log APIs to make them usable without
/// platform and availability checks.
public final class OSLog {

    private let __log: Any?

  #if canImport(os)
    @available(OSX 10.12, *)
    @usableFromInline var _log: os.OSLog {
        return __log as! os.OSLog
    }
  #endif

    private init(_ __log: Any? = nil) {
        self.__log = __log
    }

    /// Creates a custom log object.
    public convenience init(subsystem: String, category: String) {
      #if canImport(os)
        if #available(OSX 10.12, *) {
            self.init(os.OSLog(subsystem: subsystem, category: category))
        } else {
            self.init(nil)
        }
      #else
        self.init(nil)
      #endif
    }

    /// The shared default log.
    public static let disabled: OSLog = {
      #if canImport(os)
        if #available(OSX 10.12, *) {
            return OSLog(os.OSLog.disabled)
        } else {
            return OSLog(nil)
        }
      #else
        return OSLog(nil)
      #endif
    }()

    /// The shared disabled log.
    public static let `default`: OSLog = {
      #if canImport(os)
        if #available(OSX 10.12, *) {
            return OSLog(os.OSLog.default)
        } else {
            return OSLog(nil)
        }
      #else
        return OSLog(nil)
      #endif
    }()
}

/// Sends a message to the logging system.
///
/// This is a thin wrapper for Darwin's log APIs to make them usable without
/// platform and availability checks.
@inlinable public func os_log(log: OSLog = .default, _ message: StaticString, _ args: CVarArg...) {
  #if canImport(os)
    if #available(OSX 10.14, *) {
        switch args.count {
        case 1:
            os.os_log(message, log: log._log, args[0])
        case 2:
            os.os_log(message, log: log._log, args[0], args[1])
        case 3:
            os.os_log(message, log: log._log, args[0], args[1], args[2])
        case 4:
            os.os_log(message, log: log._log, args[0], args[1], args[2], args[3])
        default:
            assertionFailure("Unsupported number of arguments")
        }
    }
  #endif
}

// MARK :- OSSignpost APIs

/// The type of a signpost tracepoint.
///
/// This is a thin wrapper for Darwin's signpost APIs to make them usable without
/// platform and availability checks.
public struct OSSignpostType {

  #if canImport(os)
    @usableFromInline let _type: os.OSSignpostType?

    private init(_ _type: os.OSSignpostType?) {
        self._type = _type
    }
  #else
    private init() {}
  #endif

    /// Begins a signposted interval.
    public static let begin: OSSignpostType = {
      #if canImport(os)
        if #available(OSX 10.14, *) {
            return OSSignpostType(.begin)
        } else {
            return OSSignpostType(nil)
        }
      #else
        return OSSignpostType()
      #endif
    }()

    /// Ends a signposted interval.
    public static let end: OSSignpostType = {
      #if canImport(os)
        if #available(OSX 10.14, *) {
            return OSSignpostType(.end)
        } else {
            return OSSignpostType(nil)
        }
      #else
        return OSSignpostType()
      #endif
    }()

    /// Marks a point of interest in time with no duration.
    public static let event: OSSignpostType = {
      #if canImport(os)
        if #available(OSX 10.14, *) {
            return OSSignpostType(.event)
        } else {
            return OSSignpostType(nil)
        }
      #else
        return OSSignpostType()
      #endif
    }()
}

/// An ID to disambiguate intervals in a signpost.
///
/// This is a thin wrapper for Darwin's signpost APIs to make them usable without
/// platform and availability checks.
public struct OSSignpostID {

    private let __id: Any?

  #if canImport(os)
    @available(OSX 10.14, *)
    @usableFromInline var _id: os.OSSignpostID {
        return __id as! os.OSSignpostID
    }
  #endif

    private init(_ __id: Any?) {
        self.__id = __id
    }

    // Generates an ID guaranteed to be unique within the matching scope of the
    // provided log handle.
    public init(log: OSLog) {
      #if canImport(os)
        if #available(OSX 10.14, *) {
            self.init(os.OSSignpostID(log: log._log))
        } else {
            self.init(nil)
        }
      #else
        self.init(nil)
      #endif
    }

    /// A convenience value for signpost intervals that will never occur
    /// concurrently.
    public static let exclusive: OSSignpostID = {
      #if canImport(os)
        if #available(OSX 10.14, *) {
            return OSSignpostID(os.OSSignpostID.exclusive)
        } else {
            return OSSignpostID(nil)
        }
      #else
        return OSSignpostID(nil)
      #endif
    }()
}

/// Emits a signpost.
@inlinable public func os_signpost(
    _ type: OSSignpostType,
    log: OSLog = .default,
    name: StaticString,
    signpostID: OSSignpostID = .exclusive
) {
  #if canImport(os)
    if #available(OSX 10.14, *) {
        os.os_signpost(type: type._type!, log: log._log, name: name, signpostID: signpostID._id)
    }
  #endif
}

/// Emits a signpost.
@inlinable public func os_signpost(
    _ type: OSSignpostType,
    log: OSLog = .default,
    name: StaticString,
    signpostID: OSSignpostID = .exclusive,
    _ format: StaticString,
    _ args: CVarArg...
) {
  #if canImport(os)
    if #available(OSX 10.14, *) {
        switch args.count {
        case 0:
            os.os_signpost(type: type._type!, log: log._log, name: name, signpostID: signpostID._id, format)
        case 1:
            os.os_signpost(type: type._type!, log: log._log, name: name, signpostID: signpostID._id, format, args[0])
        case 2:
            os.os_signpost(type: type._type!, log: log._log, name: name, signpostID: signpostID._id, format, args[0], args[1])
        case 3:
            os.os_signpost(type: type._type!, log: log._log, name: name, signpostID: signpostID._id, format, args[0], args[1], args[2])
        case 4:
            os.os_signpost(type: type._type!, log: log._log, name: name, signpostID: signpostID._id, format, args[0], args[1], args[2], args[3])
        default:
            assertionFailure("Unsupported number of arguments")
        }
    }
  #endif
}
