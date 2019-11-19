/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

#if canImport(os)
import os.log
#endif

/// A custom log object that can be passed to logging functions in order to send
/// messages to the logging system.
///
/// This is a thin wrapper for Darwin's log APIs to make them usable without
/// platform and availability checks.
public final class OSLog {

    private let storage: Any?

  #if canImport(os)
    @available(macOS 10.12, *)
    @usableFromInline var log: os.OSLog {
        return storage as! os.OSLog
    }
  #endif

    private init(_ storage: Any? = nil) {
        self.storage = storage
    }

    /// Creates a custom log object.
    public convenience init(subsystem: String, category: String) {
      #if canImport(os)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
            self.init(os.OSLog(subsystem: subsystem, category: category))
        } else {
            self.init()
        }
      #else
        self.init()
      #endif
    }

    /// The shared default log.
    public static let disabled: OSLog = {
      #if canImport(os)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
            return OSLog(os.OSLog.disabled)
        } else {
            return OSLog()
        }
      #else
        return OSLog()
      #endif
    }()

    /// The shared default log.
    public static let `default`: OSLog = {
      #if canImport(os)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
            return OSLog(os.OSLog.default)
        } else {
            return OSLog()
        }
      #else
        return OSLog()
      #endif
    }()
}

/// Logging levels supported by the system.
public struct OSLogType {

    private let storage: Any?

    #if canImport(os)
      @available(macOS 10.12, *)
      @usableFromInline var `type`: os.OSLogType {
          return storage as! os.OSLogType
      }
    #endif

    private init(_ storage: Any? = nil) {
        self.storage = storage
    }

    /// The default log level.
    public static var `default`: OSLogType {
        #if canImport(os)
          if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
              return self.init(os.OSLogType.default)
          } else {
              return self.init()
          }
        #else
          return self.init()
        #endif
    }

    /// The info log level.
    public static var info: OSLogType {
        #if canImport(os)
          if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
              return self.init(os.OSLogType.info)
          } else {
              return self.init()
          }
        #else
          return self.init()
        #endif
    }

    /// The debug log level.
    public static var debug: OSLogType {
        #if canImport(os)
          if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
              return self.init(os.OSLogType.info)
          } else {
              return self.init()
          }
        #else
          return self.init()
        #endif
    }
}

/// Sends a message to the logging system.
///
/// This is a thin wrapper for Darwin's log APIs to make them usable without
/// platform and availability checks.
@inlinable public func os_log(
    _ type: OSLogType = .default,
    log: OSLog = .default,
    _ message: StaticString,
    _ args: CVarArg...
) {
  #if canImport(os)
    if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
        switch args.count {
        case 0:
            os.os_log(type.type, log: log.log, message)
        case 1:
            os.os_log(type.type, log: log.log, message, args[0])
        case 2:
            os.os_log(type.type, log: log.log, message, args[0], args[1])
        case 3:
            os.os_log(type.type, log: log.log, message, args[0], args[1], args[2])
        case 4:
            os.os_log(type.type, log: log.log, message, args[0], args[1], args[2], args[3])
        case 5:
            os.os_log(type.type, log: log.log, message, args[0], args[1], args[2], args[3], args[4])
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
    @usableFromInline let type: os.OSSignpostType

    private init(_ type: os.OSSignpostType) {
        self.type = type
    }
  #else
    private init() {}
  #endif

    /// Begins a signposted interval.
    public static let begin: OSSignpostType = {
      #if canImport(os)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
            return OSSignpostType(.begin)
        } else {
            fatalError("unreachable")
        }
      #else
        return OSSignpostType()
      #endif
    }()

    /// Ends a signposted interval.
    public static let end: OSSignpostType = {
      #if canImport(os)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
            return OSSignpostType(.end)
        } else {
            fatalError("unreachable")
        }
      #else
        return OSSignpostType()
      #endif
    }()

    /// Marks a point of interest in time with no duration.
    public static let event: OSSignpostType = {
      #if canImport(os)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
            return OSSignpostType(.event)
        } else {
            fatalError("unreachable")
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

    private let storage: Any?

  #if canImport(os)
    @available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *)
    @usableFromInline var id: os.OSSignpostID {
        return storage as! os.OSSignpostID
    }
  #endif

    private init(_ storage: Any?) {
        self.storage = storage
    }

    // Generates an ID guaranteed to be unique within the matching scope of the
    // provided log handle.
    public init(log: OSLog) {
      #if canImport(os)
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
            self.init(os.OSSignpostID(log: log.log))
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
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
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
    if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
        os.os_signpost(type.type, log: log.log, name: name, signpostID: signpostID.id)
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
    if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
        switch args.count {
        case 0:
            os.os_signpost(type.type, log: log.log, name: name, signpostID: signpostID.id, format)
        case 1:
            os.os_signpost(type.type, log: log.log, name: name, signpostID: signpostID.id, format, args[0])
        case 2:
            os.os_signpost(type.type, log: log.log, name: name, signpostID: signpostID.id, format, args[0], args[1])
        case 3:
            os.os_signpost(type.type, log: log.log, name: name, signpostID: signpostID.id, format, args[0], args[1], args[2])
        case 4:
            os.os_signpost(type.type, log: log.log, name: name, signpostID: signpostID.id, format, args[0], args[1], args[2], args[3])
        case 5:
            os.os_signpost(type.type, log: log.log, name: name, signpostID: signpostID.id, format, args[0], args[1], args[2], args[3], args[4])
        default:
            assertionFailure("Unsupported number of arguments")
        }
    }
  #endif
}
