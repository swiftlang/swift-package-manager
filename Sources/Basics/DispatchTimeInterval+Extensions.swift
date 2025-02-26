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

import Dispatch
import struct Foundation.TimeInterval

extension DispatchTimeInterval {
    public func timeInterval() -> TimeInterval? {
        switch self {
        case .seconds(let value):
            return Double(value)
        case .milliseconds(let value):
            return Double(value) / 1000
        case .microseconds(let value):
            return Double(value) / 1_000_000
        case .nanoseconds(let value):
            return Double(value) / 1_000_000_000
        default:
            return nil
        }
    }

    public func nanoseconds() -> Int? {
        switch self {
        case .seconds(let value):
            return value.multipliedReportingOverflow(by: 1_000_000_000).partialValue
        case .milliseconds(let value):
            return value.multipliedReportingOverflow(by: 1_000_000).partialValue
        case .microseconds(let value):
            return value.multipliedReportingOverflow(by: 1000).partialValue
        case .nanoseconds(let value):
            return value
        default:
            return nil
        }
    }

    public func milliseconds() -> Int? {
        switch self {
        case .seconds(let value):
            return value.multipliedReportingOverflow(by: 1000).partialValue
        case .milliseconds(let value):
            return value
        case .microseconds(let value):
            return Int(Double(value) / 1000)
        case .nanoseconds(let value):
            return Int(Double(value) / 1_000_000)
        default:
            return nil
        }
    }

    public func seconds() -> Int? {
        switch self {
        case .seconds(let value):
            return value
        case .milliseconds(let value):
            return Int(Double(value) / 1000)
        case .microseconds(let value):
            return Int(Double(value) / 1_000_000)
        case .nanoseconds(let value):
            return Int(Double(value) / 1_000_000_000)
        default:
            return nil
        }
    }

    public var descriptionInSeconds: String {
        switch self {
        case .seconds(let value):
            return "\(value)s"
        case .milliseconds(let value):
            return String(format: "%.2f", Double(value) / Double(1000)) + "s"
        case .microseconds(let value):
            return String(format: "%.2f", Double(value) / Double(1_000_000)) + "s"
        case .nanoseconds(let value):
            return String(format: "%.2f", Double(value) / Double(1_000_000_000)) + "s"
        case .never:
            return "n/a"
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        @unknown default:
            return "n/a"
        #endif
        }
    }
}

// remove when available to all platforms
#if os(Linux) || os(Windows) || os(Android) || os(OpenBSD) || os(FreeBSD)
extension DispatchTime {
    public func distance(to: DispatchTime) -> DispatchTimeInterval {
        let final = to.uptimeNanoseconds
        let point = self.uptimeNanoseconds
        let duration = Int64(bitPattern: final.subtractingReportingOverflow(point).partialValue)
        return .nanoseconds(duration >= Int.max ? Int.max : Int(duration))
    }
}
#endif
