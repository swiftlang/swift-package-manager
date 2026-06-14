//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import Foundation

public struct TestTemplateResult: Encodable {
    public var generationDuration: DispatchTimeInterval
    public var buildDuration: DispatchTimeInterval
    public var generationSuccess: Bool
    public var buildSuccess: Bool
    public var logFilePath: String?

    enum CodingKeys: String, CodingKey {
        case generationDuration, buildDuration, generationSuccess, buildSuccess, logFilePath
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.generationDuration.seconds, forKey: .generationDuration)
        try container.encode(self.buildDuration.seconds, forKey: .buildDuration)
        try container.encode(self.generationSuccess, forKey: .generationSuccess)
        try container.encode(self.buildSuccess, forKey: .buildSuccess)
        try container.encodeIfPresent(self.logFilePath, forKey: .logFilePath)
    }

    public init(
        generationDuration: DispatchTimeInterval,
        buildDuration: DispatchTimeInterval,
        generationSuccess: Bool,
        buildSuccess: Bool,
        logFilePath: String? = nil
    ) {
        self.generationDuration = generationDuration
        self.buildDuration = buildDuration
        self.generationSuccess = generationSuccess
        self.buildSuccess = buildSuccess
        self.logFilePath = logFilePath
    }
}

extension DispatchTimeInterval {
    public var seconds: TimeInterval {
        switch self {
        case .seconds(let s): return TimeInterval(s)
        case .milliseconds(let ms): return TimeInterval(Double(ms) / 1000)
        case .microseconds(let us): return TimeInterval(Double(us) / 1_000_000)
        case .nanoseconds(let ns): return TimeInterval(Double(ns) / 1_000_000_000)
        case .never: return 0
        @unknown default: return 0
        }
    }
}

public enum ShowTestTemplateOutput: String, RawRepresentable, CustomStringConvertible, ExpressibleByArgument,
    CaseIterable
{
    case matrix
    case json

    public var description: String { rawValue }
}
