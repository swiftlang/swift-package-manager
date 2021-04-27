/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Dispatch
import struct Foundation.TimeInterval

extension DispatchTimeInterval {
    func timeInterval() -> TimeInterval? {
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

    func milliseconds() -> Int? {
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

    func seconds() -> Int? {
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
}

// remove when available to all platforms
#if os(Linux) || os(Windows) || os(Android)
extension DispatchTime {
    public func distance(to: DispatchTime) -> DispatchTimeInterval {
        let duration = to.uptimeNanoseconds - self.uptimeNanoseconds
        return .nanoseconds(duration >= Int.max ? Int.max : Int(duration))
    }
}
#endif
